# frozen_string_literal: true

return if RUBY_ENGINE == "opal"

require "stringio"
require "leptris"

module Moxml
  module Adapter
    # Adapter over the leptris FFI binding (libleptris C library).
    #
    # libleptris provides DOM parsing, a native XPath 1.0 engine, SAX,
    # and serialization. It has no first-class XML declaration or
    # programmatic DOCTYPE, so those live in CustomizedLeptris value
    # objects stored through NativeAttachment.
    class Leptris < Base
      # The binding floor (issue #149): 1.9.32 carried the traverse
      # fix (leptris-ruby#89) and made built documents reflect their
      # parts immediately (leptris-ruby#91); the document node
      # (1.9.26), DTDATTR (1.9.8), and the batch child-pointer read
      # (1.7.0) surfaces predate it. Older bindings are not eligible
      # for the default (see Config.leptris_preferred_available?) and
      # the adapter no longer carries accommodation paths for them.
      MINIMUM_BINDING_VERSION = "1.9.32"

      # leptris-ruby#103: prefixed attribute tests inside predicates
      # stopped resolving through the document's in-scope declarations
      # on released 1.9.37–1.9.39; 1.9.40 (engine 1.9.14+) restored
      # the fallback. Older bindings keep the Ruby-engine routing in
      # native_expression?.
      PREFIXED_ATTR_PREDICATES_NATIVE =
        Gem::Version.new(::Leptris::VERSION) >= Gem::Version.new("1.9.40")

      NO_PARSE_ERRORS = [].freeze
      private_constant :NO_PARSE_ERRORS

      # Cohesive clusters extracted from this class — the adapter
      # protocol surface is unchanged; the modules hold the document
      # parts assembly, the entity-marker pipeline, and the bulk
      # materializer respectively.
      autoload :DocumentParts, "moxml/adapter/leptris/document_parts"
      autoload :Markers, "moxml/adapter/leptris/markers"
      autoload :Materialize, "moxml/adapter/leptris/materialize"
      autoload :Serialize, "moxml/adapter/leptris/serialize"
      autoload :LeptrisSAXBridge, "moxml/adapter/leptris/sax_bridge"
      extend Serialize
      extend DocumentParts
      extend Markers
      extend Materialize

      class << self
        def attachments
          @attachments ||= Moxml::NativeAttachment.new
        end

        def set_root(doc, element)
          doc.root = element
        end

        def parse(xml, options = {}, _context = nil)
          xml_string = xml.is_a?(IO) || xml.is_a?(StringIO) ? xml.read : xml.to_s
          # The marker flag rides preprocess's own `&` scan — no
          # second full-buffer probe (issue #132 parse-side note).
          processed, entity_markers = Entity.preprocess_with_marker_flag(xml_string)

          # readonly: true (issue #133): the binding memoizes reads and
          # refuses mutations — the parse-and-read lifecycle for
          # multi-pass consumers (comparison, diff, signature).
          # dtdattr: true opts into DTD ATTLIST default materialization
          # (off by default since libleptris 1.9.8, matching libxml2).
          native_doc = begin
            ::Leptris::XML::Document.parse(
              processed,
              readonly: options[:readonly] == true,
              options: dtdattr_parse_options(options),
            )
          rescue ::Leptris::XML::ParseError => e
            # libleptris has no recovery mode that survives unclosed
            # tags; non-strict callers get an empty document, matching
            # the Libxml adapter's non-strict behavior. The fatal
            # error rides the document as parse diagnostics (issue
            # #147) — otherwise nothing says why it came back empty.
            raise Moxml::ParseError.new(e.message) if options[:strict]

            recover_errors = [e.message]
            create_document
          end
          ctx = _context || Context.new(:leptris)
          doc = Document.new(native_doc, ctx)

          record_source_declaration(native_doc, processed)
          attachments.set(native_doc, :entity_markers, entity_markers)
          attachments.set(native_doc, :parse_errors, recover_errors) if recover_errors

          doc
        end

        # nil unless DTDATTR is requested — the binding treats a nil
        # options hash as plain defaults (defaults exclude ATTLIST
        # defaults, matching libxml2/Nokogiri semantics).
        def dtdattr_parse_options(options)
          options[:dtdattr] == true ? ::Leptris::XML::ParseOptions.dtdattr : nil
        end

        def parse_errors(native_doc)
          attachments.get(native_doc, :parse_errors) || NO_PARSE_ERRORS
        end

        def create_document(_native_doc = nil)
          ::Leptris::XML::Document.create
        end

        def create_native_element(name, owner_doc = nil)
          (owner_doc || create_document).create_element(name.to_s)
        end

        def create_native_text(content, owner_doc = nil)
          (owner_doc || create_document).create_text_node(content)
        end

        def create_native_cdata(content, owner_doc = nil)
          (owner_doc || create_document).create_cdata(content)
        end

        def create_native_comment(content, owner_doc = nil)
          (owner_doc || create_document).create_comment(content)
        end

        def create_native_processing_instruction(target, content)
          doc = create_document
          doc.create_processing_instruction(target.to_s, content.to_s)
        end

        def create_native_doctype(name, external_id, system_id)
          CustomizedLeptris::Doctype.new(name, external_id, system_id)
        end

        def create_native_declaration(version, encoding, standalone)
          CustomizedLeptris::Declaration.new(version, encoding, standalone)
        end

        def create_native_entity_reference(name)
          CustomizedLeptris::EntityReference.new(name)
        end

        def entity_reference_name(node)
          node.name if node.is_a?(CustomizedLeptris::EntityReference)
        end

        def declaration_attribute(declaration, attr_name)
          declaration.public_send(attr_name) if attr_matches?(attr_name)
        end

        def set_declaration_attribute(declaration, attr_name, value)
          declaration.public_send("#{attr_name}=", value) if attr_matches?(attr_name)
        end

        def attr_matches?(attr_name)
          %w[version encoding standalone].include?(attr_name.to_s)
        end
        private :attr_matches?

        def has_declaration?(native_doc, _wrapper)
          return true if attachments.get(native_doc, :declaration)

          attachments.key?(native_doc, :had_source_declaration) &&
            attachments.get(native_doc, :had_source_declaration)
        end

        def remove_declaration(native_doc)
          attachments.delete(native_doc, :declaration)
          attachments.delete(native_doc, :had_source_declaration)
        end

        def create_native_namespace(element, prefix, uri)
          element.add_namespace_definition(prefix, uri)
        end

        def set_namespace(node, namespace)
          return set_attribute_namespace(node, namespace) if node.is_a?(::Leptris::XML::Attr)

          element = node
          prefix = namespace.is_a?(String) ? nil : namespace.prefix
          uri = namespace.is_a?(String) ? namespace : namespace.href
          if prefix.nil? || prefix.empty?
            element.default_namespace = uri.to_s
            # Drop any prefix from the element name: a default namespace
            # never applies to a prefixed name.
            element.name = element.name.split(":", 2)[-1] if element.name.include?(":")
          else
            element.add_namespace_definition(prefix, uri.to_s)
            element.name = "#{prefix}:#{element.name.split(':', 2)[-1]}"
          end
          element
        end

        # Attr is an immutable value object: namespace changes go
        # through the owning element, recreating the attribute with a
        # qualified name, and yield a fresh native for the wrapper.
        def set_attribute_namespace(attr, namespace)
          element = attr.element
          local = attr.name.include?(":") ? attr.name.split(":", 2)[1] : attr.name
          value = attr.value
          element.remove_attribute(attr.name)
          prefix = namespace.is_a?(String) ? nil : namespace.prefix
          uri = namespace.is_a?(String) ? namespace : namespace.href
          qualified = prefix.nil? || prefix.empty? ? local : "#{prefix}:#{local}"
          element[qualified] = value
          if prefix && !prefix.empty? && !uri.to_s.empty? && !resolve_prefix_ns(element, prefix)
            element.add_namespace_definition(prefix, uri.to_s)
          end
          element.attribute_nodes.reverse.find { |candidate| candidate.name == qualified }
        end

        def namespace(node)
          # The binding resolves Attr#namespace to the declaration but
          # without the prefix; when the qualified name carries one,
          # prefer the in-scope declaration that binds it so wrappers
          # keep prefix and uri.
          if node.is_a?(::Leptris::XML::Attr) &&
              (prefix = node.prefix || prefix_part(node.name))
            resolved = resolve_prefix_ns(node.element, prefix)
            return resolved if resolved
          end

          ns = node.namespace
          return ns unless ns.nil?

          # Set-side namespaces (created attributes, renamed elements)
          # carry a prefix the native resolver did not bind; resolve
          # through the scope chain so wrapper-level access stays
          # XML-correct.
          owner = node.is_a?(::Leptris::XML::Attr) ? node.element : node
          prefix = if node.is_a?(::Leptris::XML::Attr)
                     node.prefix || prefix_part(node.name)
                   else
                     prefix_part(node.name)
                   end
          return nil if prefix.nil?

          resolve_prefix_ns(owner, prefix)
        end

        # Nearest in-scope declaration of prefix, walking owner then
        # ancestors. Unbound prefix → nil. Returns the Namespace object
        # so wrappers keep prefix and uri.
        def resolve_prefix_ns(owner, prefix)
          current = owner
          while current.is_a?(::Leptris::XML::Element)
            hit = current.namespace_definitions.find { |ns| ns.prefix == prefix }
            return hit if hit

            current = current.parent
          end
          nil
        end

        def prefix_part(name)
          name.include?(":") ? name.split(":", 2)[0] : nil
        end

        def processing_instruction_target(node)
          node.target
        end

        def node_type(node)
          # Frequency-ordered: elements and text dominate every real
          # document, and Node.wrap dispatches here once per cold
          # wrap. CDATA must precede Text (CDATA < Text in the
          # binding).
          case node
          when ::Leptris::XML::Element then :element
          when ::Leptris::XML::CDATA then :cdata
          when ::Leptris::XML::Text, CustomizedLeptris::TextSegment then :text
          when ::Leptris::XML::Attr then :attribute
          when ::Leptris::XML::Comment then :comment
          when ::Leptris::XML::ProcessingInstruction, CustomizedLeptris::DocumentPI then :processing_instruction
          when ::Leptris::XML::Document then :document
          when ::Leptris::XML::DocType, CustomizedLeptris::Doctype then :doctype
          when CustomizedLeptris::Declaration then :declaration
          when CustomizedLeptris::EntityReference then :entity_reference
          else :unknown
          end
        end

        def node_name(node)
          return node.root_name if node.is_a?(::Leptris::XML::DocType)
          return node.target if node.is_a?(CustomizedLeptris::DocumentPI)

          node.name.to_s.dup.force_encoding("UTF-8")
        end

        def set_node_name(node, name)
          case node
          when ::Leptris::XML::ProcessingInstruction, CustomizedLeptris::DocumentPI then node.target = name
          else node.name = name
          end
        end

        def duplicate_node(node)
          case node
          when CustomizedLeptris::Declaration
            CustomizedLeptris::Declaration.new(node.version, node.encoding, node.standalone)
          when CustomizedLeptris::Doctype
            CustomizedLeptris::Doctype.new(node.name, node.external_id, node.system_id)
          when CustomizedLeptris::EntityReference
            CustomizedLeptris::EntityReference.new(node.name)
          when CustomizedLeptris::DocumentPI
            CustomizedLeptris::DocumentPI.new(node.target, node.data, node.parent_doc)
          else
            node.dup
          end
        end

        def children(node)
          case node
          when ::Leptris::XML::Document
            assemble_document_children(node)
          when CustomizedLeptris::Declaration, CustomizedLeptris::Doctype,
               CustomizedLeptris::EntityReference, CustomizedLeptris::TextSegment,
               CustomizedLeptris::DocumentPI,
               # Terminal node kinds pay an FFI round trip for an empty
               # list; unfiltered recursions visit every text node.
               ::Leptris::XML::Text, ::Leptris::XML::Comment,
               ::Leptris::XML::CDATA, ::Leptris::XML::ProcessingInstruction,
               ::Leptris::XML::Attr
            []
          else
            natives = node.children.to_a
            # Parse records whether the preprocessed source held any
            # entity markers, and the ER builder path flips the flag
            # when it mints one. A false flag lets traversal skip the
            # marker split — including the per-text content fetch that
            # dominates cold children cost. Cross-document moves of
            # marker-bearing text into an entity-free document degrade
            # to literal text.
            return natives if attachments.get(node.document, :entity_markers) == false

            split_entity_markers(natives, node)
          end
        end

        def parent(node)
          case node
          when ::Leptris::XML::Document then nil
          when CustomizedLeptris::Declaration, CustomizedLeptris::Doctype,
               CustomizedLeptris::DocumentPI then node.parent_doc
          when CustomizedLeptris::TextSegment, CustomizedLeptris::EntityReference then node.parent
          else
            # The binding reports the root element as parentless; the
            # moxml contract roots at the document.
            node.parent || (node.document&.root == node ? node.document : nil)
          end
        end

        def next_sibling(node)
          node.next_sibling if node.is_a?(::Leptris::XML::Node)
        end

        def previous_sibling(node)
          node.previous_sibling if node.is_a?(::Leptris::XML::Node)
        end

        def document(node)
          case node
          when ::Leptris::XML::Document then node
          when CustomizedLeptris::Declaration, CustomizedLeptris::Doctype then node.parent_doc
          else node.document
          end
        end

        def root(document)
          document.root
        end

        def line_number(node)
          return nil unless node.is_a?(::Leptris::XML::Node)

          line = node.line
          line.zero? ? nil : line
        end

        def attributes(element)
          element.attribute_nodes
        end

        def attribute_element(attr)
          attr.element
        end

        def attribute_name(attr)
          # leptris Attr names are qualified; the wrapper composes the
          # prefix, so expose the local part.
          return attr.name.split(":", 2)[1] if attr.name.include?(":")

          attr.name.to_s.dup.force_encoding("UTF-8")
        end

        def set_attribute(element, name, value)
          element[name.to_s] = value.to_s
        end

        def set_attribute_name(attr, name)
          # Attr is an immutable value object; renames go through the
          # element and yield a fresh native, which the wrapper adopts.
          element = attr.element
          value = attr.value
          element.remove_attribute(attr.name)
          element[name.to_s] = value
          element.attribute_nodes.reverse.find { |candidate| candidate.name == name.to_s }
        end

        def set_attribute_value(attr, value)
          attr.value = value.to_s
          attr
        end

        def get_attribute(element, name)
          element.attribute_nodes.find { |attr| attr.name == name.to_s }
        end

        def get_attribute_value(element, name)
          element[name.to_s]
        end

        def remove_attribute(element, name)
          element.remove_attribute(name.to_s)
        end

        def remove_attribute_native(attr)
          attr.element.remove_attribute(attr.name)
          attr
        end

        def add_child(parent, child)
          case parent
          when ::Leptris::XML::Document then add_document_child(parent, child)
          else
            if child.is_a?(CustomizedLeptris::EntityReference)
              marker = parent.document.create_text_node("#{Entity::MARKER}#{child.name};")
              parent.add_child(marker)
              attachments.set(parent.document, :entity_markers, true)
              return child
            end
            child = parent.document.create_text_node(child) if child.is_a?(String)
            parent.add_child(child)
          end
        end

        def add_previous_sibling(node, new_node)
          # A PI inserted before the root lives at document level in
          # libleptris's model, not in the element tree.
          if new_node.is_a?(::Leptris::XML::ProcessingInstruction) &&
              node.document&.root == node
            node.document.add_pi(new_node.target, new_node.content.to_s)
            return new_node
          end
          node.add_previous_sibling(new_node)
        end

        def add_next_sibling(node, new_node)
          node.add_next_sibling(new_node)
        end

        def remove(node)
          case node
          when CustomizedLeptris::Declaration
            remove_declaration(node.parent_doc) if node.parent_doc
          when CustomizedLeptris::Doctype
            attachments.delete(node.parent_doc, :doctype) if node.parent_doc
          when CustomizedLeptris::EntityReference
            marker_text_for(node.parent, node.name)&.unlink
          when CustomizedLeptris::DocumentPI
            raise Moxml::NotImplementedError.new(
              "libleptris has no document-level PI removal",
              adapter: :leptris,
              feature: :remove,
            )
          else
            node.unlink
          end
        end

        def replace(node, new_node)
          return node.replace(new_node) if node.is_a?(::Leptris::XML::Element)

          # libleptris only offers element-anchored insertion, so a
          # content node (text/comment/CDATA/PI) is replaced by
          # unlinking and re-inserting: after an element sibling when
          # one exists, else appended (end-of-list) to the parent.
          parent = node.parent
          unless parent
            raise Moxml::DocumentStructureError.new(
              "cannot replace a detached node",
            )
          end

          prev = node.previous_sibling
          node.unlink
          if prev.is_a?(::Leptris::XML::Element)
            prev.add_next_sibling(new_node)
          else
            parent.add_child(new_node)
          end
          new_node
        end

        def replace_children(node, new_children)
          node.children = new_children
        end

        def text_content(node)
          case node
          when ::Leptris::XML::Document then node.root ? node.root.content : ""
          when CustomizedLeptris::Declaration, CustomizedLeptris::Doctype,
               CustomizedLeptris::EntityReference
            ""
          when CustomizedLeptris::TextSegment then node.content
          else node.content.to_s
          end
        end

        def inner_text(node)
          # moxml semantic: direct text children only — no descendant
          # text (that is #text), no comments. Entity references
          # contribute their serialized form.
          children(node).filter_map do |child|
            case child
            when CustomizedLeptris::EntityReference then "&#{child.name};"
            when ::Leptris::XML::CDATA then child.content
            when ::Leptris::XML::Text, CustomizedLeptris::TextSegment
              child.content.to_s.dup.force_encoding("UTF-8")
            end
          end.join
        end

        def set_text_content(node, content)
          case node
          when ::Leptris::XML::Document
            node.root&.content = content.to_s
          else
            node.content = content.to_s
          end
        end

        def cdata_content(node)
          node.content
        end

        def set_cdata_content(node, content)
          node.content = content.to_s
        end

        def comment_content(node)
          node.content
        end

        def set_comment_content(node, content)
          node.content = content.to_s
        end

        def processing_instruction_content(node)
          node.content
        end

        def set_processing_instruction_content(node, content)
          node.data = content.to_s
        end

        def namespace_prefix(namespace)
          # Attr#namespace is the bare URI string in leptris 1.9+ (the
          # C model: a namespace handle IS the URI); attributes carry
          # their prefix on the Attr itself.
          return nil if namespace.is_a?(String)

          namespace.prefix
        end

        def namespace_uri(namespace)
          return namespace if namespace.is_a?(String)

          namespace.href
        end

        def namespace_definitions(element)
          element.namespace_definitions
        end

        def doctype_name(node)
          node.is_a?(CustomizedLeptris::Doctype) ? node.name : node.root_name
        end

        def doctype_external_id(node)
          node.is_a?(CustomizedLeptris::Doctype) ? node.external_id : node.public_id
        end

        def doctype_system_id(node)
          node.system_id
        end

        # XPath prefers libleptris' native C engine (three orders of
        # magnitude faster than the Ruby engine) for document-context
        # queries, with a conservative gate: the Ruby engine handles
        # element-context evaluation (native relative-context
        # semantics are not contract-verified), variable references,
        # and expressions whose results are attribute nodes (native
        # returns those without name accessors). Both engines resolve
        # expression prefixes against document-declared namespaces.
        NATIVE_XPATH_CACHE = XPath::Cache.new(100)
        # The gate decision is expression-intrinsic; re-walking the
        # cached AST three times per xpath call cost ~23% of repeated
        # selective queries, so the boolean caches beside it.
        NATIVE_GATE_CACHE = XPath::Cache.new(100)

        def xpath(node, expression, namespaces = {})
          native = native_xpath(node, expression, namespaces)
          return native unless native.nil?

          engine_xpath(node, expression, namespaces)
        end

        def at_xpath(node, expression, namespaces = {})
          native = native_xpath(node, expression, namespaces, first_only: true)
          return native unless native.nil?

          result = engine_xpath(node, expression, namespaces)
          result.is_a?(Array) ? result.first : result
        end

        # @return [Array, Object, nil] native results, or nil when the
        #   query must run on the Ruby engine
        def native_xpath(node, expression, namespaces, first_only: false)
          return nil unless native_context_node?(node)
          return nil unless native_expression?(expression)
          # The binding reports the root element parentless while moxml
          # roots it at the document, so parent-axis queries from the
          # root element keep the Ruby engine.
          if node.is_a?(::Leptris::XML::Element) &&
              node.document&.root.equal?(node) &&
              expression_uses_parent_axis?(expression)
            return nil
          end

          compiled = NATIVE_XPATH_CACHE.get_or_set(expression) do
            ::Leptris::XML::XPath.compile(expression)
          end
          result = if namespaces && !namespaces.empty?
                     compiled.eval(node, namespaces)
                   else
                     compiled.eval(node)
                   end
          case result
          when ::Leptris::XML::NodeSet
            nodes = result.to_a
            first_only ? nodes.first : nodes
          else
            result
          end
        rescue ::Leptris::XML::XPathError
          # Not supported by the native engine — the Ruby engine is a
          # full XPath 1.0 implementation, including Moxml's syntax
          # errors for invalid expressions.
          nil
        end

        def native_context_node?(node)
          node.is_a?(::Leptris::XML::Document) ||
            node.is_a?(::Leptris::XML::Element)
        end

        def expression_uses_parent_axis?(expression)
          ast = XPath::Parser.parse_with_cache(expression)
          contains_parent_axis?(ast)
        rescue XPath::SyntaxError
          true
        end

        def contains_parent_axis?(ast)
          return true if ast.type == :parent
          return true if ast.type == :axis && ast.children.first == "parent"

          ast.children.any? do |child|
            child.is_a?(XPath::AST::Node) && contains_parent_axis?(child)
          end
        end

        # Document-context queries without variable references,
        # attribute-node results, or the nokogiri-compat xmlns:
        # reserved prefix convention.
        def native_expression?(expression)
          NATIVE_GATE_CACHE.get_or_set(expression) do
            ast = XPath::Parser.parse_with_cache(expression)
            next false if ast_contains_type?(ast, :variable)
            next false if uses_xmlns_prefix?(ast)
            next false if !PREFIXED_ATTR_PREDICATES_NATIVE && prefixed_attribute_test?(ast)

            !selects_attribute_results?(ast)
          end
        rescue XPath::SyntaxError
          false
        end

        def ast_contains_type?(ast, type)
          return true if ast.type == type

          ast.children.any? do |child|
            child.is_a?(XPath::AST::Node) && ast_contains_type?(child, type)
          end
        end

        # xmlns:name is a nokogiri-compat convention addressing
        # elements in the default namespace; only the Ruby engine
        # implements it.
        def uses_xmlns_prefix?(ast)
          return true if ast.type == :test && ast.value[:namespace] == "xmlns"

          ast.children.any? do |child|
            child.is_a?(XPath::AST::Node) && uses_xmlns_prefix?(child)
          end
        end

        def selects_attribute_results?(ast)
          case ast.type
          when :pipe, :union, :filter_expr
            ast.children.any? { |child| selects_attribute_results?(child) }
          when :absolute_path, :relative_path
            step = ast.children.last
            step = step.children.first if step.type == :step_with_predicates
            step.type == :axis && step.children.first == "attribute"
          else
            false
          end
        end

        # Released native engines 1.9.37–1.9.39 do not match prefixed
        # attribute tests inside predicates (@p:kind='a'); the Ruby
        # engine does. An attribute test is a :test whose parent axis
        # is "attribute"; bare ones (namespace nil) stay native.
        # Retired above PREFIXED_ATTR_PREDICATES_NATIVE (1.9.40+).
        def prefixed_attribute_test?(ast, parent_axis = nil)
          if ast.type == :test && parent_axis == "attribute"
            ns = ast.value[:namespace]
            return true if ns && !ns.empty? && ns != "xmlns"
          end

          axis = ast.children.first if ast.type == :axis

          ast.children.any? do |child|
            child.is_a?(XPath::AST::Node) &&
              prefixed_attribute_test?(child, axis || (child.type == :axis ? nil : parent_axis))
          end
        end

        def engine_xpath(node, expression, namespaces = {})
          unless node.is_a?(Moxml::Node)
            node = Moxml::Node.wrap(node, Context.new(:leptris))
          end

          ast = XPath::Parser.parse(expression)
          proc = XPath::Compiler.compile_with_cache(ast, namespaces: namespaces)
          result = proc.call(node)

          case result
          when Array, NodeSet
            nodes = result.is_a?(NodeSet) ? result.to_a : result
            seen = {}.compare_by_identity
            nodes.map { |n| n.is_a?(Moxml::Node) ? n.native : n }
              .select do |native|
                if seen.key?(native)
                  false
                else
                  seen[native] = true
                  true
                end
              end
          else
            result
          end
        end

        def sax_parse(xml, handler)
          bridge = LeptrisSAXBridge.new(handler)
          xml_string = xml.is_a?(IO) || xml.is_a?(::StringIO) ? xml.read : xml.to_s
          ::Leptris::XML::SAX::Parser.new(bridge).parse(xml_string)
        rescue ::Leptris::XML::ParseError, ::Leptris::XML::Error => e
          handler.on_error(Moxml::ParseError.new(e.message))
        end

        private

        # The variable-length \s* gap after \A defeats Onigmo's anchor
        # optimization, forcing a full-buffer scan — 6.5 ms on a 1 MB
        # document without a declaration (the common case). Match a
        # head slice instead; fall back to the full string only when
        # the head is all whitespace (pathological prefixes).
        SOURCE_DECLARATION_RE = /\A\s*<\?xml\b/
        private_constant :SOURCE_DECLARATION_RE

        def record_source_declaration(native_doc, xml_string)
          head = xml_string[0, 256]
          had = if head.match?(SOURCE_DECLARATION_RE)
                  true
                elsif head.match?(/\A\s*\z/)
                  xml_string.match?(SOURCE_DECLARATION_RE)
                else
                  false
                end
          attachments.set(native_doc, :had_source_declaration, had)
        end
      end
    end
  end
end
