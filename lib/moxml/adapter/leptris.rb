# frozen_string_literal: true

return if RUBY_ENGINE == "opal"

require "stringio"
require "leptris"
# leptris-ruby 1.9.0 regression (leptris-ruby#53): the eager ffi load
# shadows the Leptris::XML autoload manifest, leaving Document/Element
# unreachable. Loading the manifest explicitly is a no-op when the gem
# is fixed.
require "leptris/xml"

module Moxml
  module Adapter
    # Adapter over the leptris FFI binding (libleptris C library).
    #
    # libleptris provides DOM parsing, a native XPath 1.0 engine, SAX,
    # and serialization. It has no first-class XML declaration or
    # programmatic DOCTYPE, so those live in CustomizedLeptris value
    # objects stored through NativeAttachment.
    class Leptris < Base
      # libleptris 1.9.7 (leptris-ruby 1.9.26): Document#node exposes
      # the libxml2-model document node — prolog/epilog parts in
      # document order. Older bindings keep the flat pre-root PI path.
      DOC_NODE_SUPPORTED = ::Leptris::XML::Document.method_defined?(:node)
      # libleptris 1.9.8 (leptris-ruby 1.9.30): plain parse excludes
      # DTD ATTLIST defaults, matching libxml2/Nokogiri semantics;
      # ParseOptions::DTDATTR opts in (leptris/leptris#606).
      DTDATTR_SUPPORTED = ::Leptris::XML::ParseOptions.const_defined?(:DTDATTR)
      # leptris-ruby 1.9.32 (#89): traverse is subtree-bounded again —
      # earlier 1.9.x walks followed the document chain and swept
      # following siblings, so element materialize had to fall back
      # to the generic wrapper walk.
      TRAVERSE_SUBTREE_BOUNDED =
        Gem::Version.new(::Leptris::VERSION) >= Gem::Version.new("1.9.32")

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
            # the Libxml adapter's non-strict behavior.
            raise Moxml::ParseError.new(e.message) if options[:strict]

            create_document
          end
          ctx = _context || Context.new(:leptris)
          doc = Document.new(native_doc, ctx)

          record_source_declaration(native_doc, processed)
          attachments.set(native_doc, :entity_markers, entity_markers)

          doc
        end

        # nil when DTDATTR is unsupported or not requested — the
        # binding treats a nil options hash as plain defaults.
        def dtdattr_parse_options(options)
          return nil unless DTDATTR_SUPPORTED && options[:dtdattr] == true

          ::Leptris::XML::ParseOptions.dtdattr
        end

        # Issue #134: deterministic release of the C tree. The binding
        # clears its wrapper cache and raises UseAfterFreeError on
        # later access; moxml-side attachments for the document are
        # swept too (the context wrapper identity map self-cleans via
        # its size valve).
        DOCUMENT_ATTACHMENT_KEYS = %i[
          entity_markers doc_pi_nodes declaration doctype
          had_source_declaration document_text
        ].freeze

        def free_document(native)
          DOCUMENT_ATTACHMENT_KEYS.each { |key| attachments.delete(native, key) }
          native.free
          nil
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

        # Marker presence is a document-level fact: parse records it,
        # the ER builder path flips it, and the split/restore scans
        # consult it. Customized natives only exist as split products
        # of marker-bearing text, so they always report true.
        def entity_bearing?(native)
          case native
          when CustomizedLeptris::Declaration, CustomizedLeptris::Doctype,
               CustomizedLeptris::EntityReference, CustomizedLeptris::TextSegment,
               CustomizedLeptris::DocumentPI
            true
          else
            doc = native.document
            doc.nil? || attachments.get(doc, :entity_markers) != false
          end
        end

        # Bulk materialization (issue #132): leptris_node_traverse
        # walks the subtree with one FFI call; the only per-node cost
        # is the C->Ruby callback and the property reads below. No
        # Moxml::Node or Attribute wrapper is allocated.
        def bulk_materialize?
          true
        end

        def materialize_records(native, &block)
          doc = native.is_a?(::Leptris::XML::Document) ? native : native.document
          # Marker-bearing text needs the split pipeline (children-level
          # ER expansion); the bulk path has no marker handling.
          return nil if doc.nil? || attachments.get(doc, :entity_markers)

          # On bindings whose traverse follows the document chain
          # (leptris 1.9.28–1.9.31), element materialize falls back to
          # the generic wrapper walk — only document materialization
          # can filter safely there (issue #140).
          root = if native.is_a?(::Leptris::XML::Document)
                   doc.root
                 else
                   return nil unless TRAVERSE_SUBTREE_BOUNDED

                   native
                 end
          return nil if root.nil?

          depth_memo = {}.compare_by_identity
          root.traverse do |node|
            depth = material_depth_in_subtree(node, root, depth_memo)
            next if depth.nil?

            record = case node
                     when ::Leptris::XML::Element
                       element_material_record(node, depth)
                     when ::Leptris::XML::CDATA
                       # CDATA < Text in the binding: this arm must come
                       # first or CDATA content reports as text.
                       text_material_record(:cdata, node.content, depth)
                     when ::Leptris::XML::Text
                       text_material_record(:text, node.content, depth)
                     when ::Leptris::XML::Comment
                       text_material_record(:comment, node.content, depth)
                     when ::Leptris::XML::ProcessingInstruction
                       text_material_record(:processing_instruction, node.content, depth)
                         .merge(qname: node.target)
                     end
            yield(record) if record
          end
          true
        end

        def element_material_record(node, depth)
          attributes = node.each_attribute.map do |attr|
            # Local name + separate prefix, matching the generic
            # path's resolver semantics (moxml's canonical shape).
            name = attr.name
            prefix = attr.prefix
            name = name.split(":", 2)[1] || name if prefix
            [name, attr.value, attr.namespace_uri, prefix]
          end
          ns = node.namespace
          {
            kind: :element,
            qname: node.name,
            prefix: node.prefix,
            namespace_uri: ns&.href,
            # Own declarations only — same shape as the generic
            # path's Element#declared_namespaces (issue #138).
            namespaces: begin
              decls = node.namespace_definitions.map { |d| [d.prefix, d.href] }
              decls.empty? ? Materializer::EMPTY_ATTRIBUTES : decls
            end,
            attributes: attributes,
            text: nil,
            depth: depth,
          }
        end

        def text_material_record(kind, text, depth)
          {
            kind: kind,
            qname: nil,
            prefix: nil,
            namespace_uri: nil,
            namespaces: Materializer::EMPTY_ATTRIBUTES,
            attributes: Materializer::EMPTY_ATTRIBUTES,
            text: text,
            depth: depth,
          }
        end

        # Depth relative to the subtree root, or nil when the node
        # lies outside it (traverse follows the document chain since
        # leptris 1.9.28, so epilog siblings can appear in the
        # stream). Binding wrappers are address-stable and #parent is
        # memoized, so each edge resolves once through the
        # identity-keyed memo.
        def material_depth_in_subtree(node, root, memo)
          memo[node] ||= if node.equal?(root)
                           0
                         else
                           parent = node.parent
                           if parent.nil? || parent.is_a?(::Leptris::XML::Document)
                             nil
                           else

                             parent_depth = material_depth_in_subtree(parent, root, memo)
                             parent_depth.nil? ? nil : parent_depth + 1

                           end
                         end
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

        # Expand marker-bearing text nodes into the child sequence the
        # moxml contract exposes: text, EntityReference, text, ...
        def split_entity_markers(natives, parent)
          result = []
          natives.each do |child|
            # FFI Text#content returns a fresh unfrozen BINARY string:
            # retag in place (dup would be a throwaway allocation), but
            # before include? — BINARY.include? with the UTF-8 marker raises
            if child.is_a?(::Leptris::XML::Text)
              content = child.content
              content.force_encoding("UTF-8")
            end
            if content&.include?(Entity::MARKER)
              content.scan(/([^#{Entity::MARKER}]*)(?:#{Entity::MARKER}([\w.:-]+);)?/o) do
                text_part = Regexp.last_match(1)
                name = Regexp.last_match(2)
                result << CustomizedLeptris::TextSegment.new(text_part, parent) unless text_part.empty?
                result << CustomizedLeptris::EntityReference.new(name) if name
              end
            else
              result << child
            end
          end
          result
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

        def serialize(node, options = {})
          # Entity restoration belongs to the wrapper layer
          # (Node#to_xml runs adapter.restore_entities for every
          # adapter); doing it here scanned the output a second time.
          normalize_serialization(raw_serialize(node, options), options)
        end

        def raw_serialize(node, options)
          # CDATA must precede Text in this chain: CDATA < Text in the
          # binding, so a Text branch first would swallow CDATA nodes.
          case node
          when CustomizedLeptris::Declaration, CustomizedLeptris::Doctype,
               CustomizedLeptris::EntityReference, CustomizedLeptris::DocumentPI
            return node.to_xml
          when ::Leptris::XML::CDATA
            return XmlEmitter.cdata(node.content)
          when ::Leptris::XML::Comment
            return "<!--#{node.content}-->"
          when ::Leptris::XML::ProcessingInstruction
            content = node.content.to_s
            return content.empty? ? "<?#{node.target}?>" : "<?#{node.target} #{content}?>"
          when ::Leptris::XML::Text, CustomizedLeptris::TextSegment
            return XmlEmitter.escape_text(node.content.to_s)
          when ::Leptris::XML::Document
            return serialize_document(node, options)
          end

          include_decl = options.fetch(:declaration) do
            options[:no_declaration] ? false : document_has_declaration?(node)
          end
          node.to_xml(
            indent: options.fetch(:indent, 0),
            no_decl: !include_decl,
            encoding: options[:encoding],
          )
        end

        # moxml canonical serialization: apostrophes stay literal
        # (only & < > " are escaped) and empty elements expand when the
        # caller asked for it — matching the other adapters' contract.
        # Runs segment-aware: CDATA content is literal and must not be
        # touched.
        # Regions whose content is literal and must never be rewritten.
        # Scanned positionally (String#index), not with a regex: the
        # scan is linear in the input length, so pathological document
        # content cannot blow up the serializer.
        LITERAL_REGIONS = {
          "<!--" => "-->",
          "<![CDATA[" => "]]>",
          "<?" => "?>",
        }.freeze

        def normalize_serialization(xml, options)
          needs_apos = xml.include?("&apos;")
          needs_expand = options[:expand_empty] && xml.include?("/>")
          return xml unless needs_apos || needs_expand

          out = +""
          pos = 0
          while pos < xml.length
            opener_at, terminator = next_literal_region(xml, pos)
            if opener_at.nil?
              out << normalize_markup(xml[pos..], needs_apos, needs_expand)
              break
            end

            out << normalize_markup(xml[pos...opener_at], needs_apos, needs_expand)
            search_from = opener_at + opener_at_offset(terminator)
            close = xml.index(terminator, search_from)
            close_end = close.nil? ? xml.length : close + terminator.length
            out << xml[opener_at...close_end]
            pos = close_end
          end
          out
        end

        # Nearest literal region at/after from: [position, terminator].
        def next_literal_region(xml, from)
          best = nil
          best_terminator = nil
          LITERAL_REGIONS.each do |opener, terminator|
            idx = xml.index(opener, from)
            next if idx.nil?

            if best.nil? || idx < best
              best = idx
              best_terminator = terminator
            end
          end
          best.nil? ? nil : [best, best_terminator]
        end

        # Search for a terminator past its opener's overlap-safe offset
        # ("-->" cannot start inside "<!--").
        def opener_at_offset(terminator)
          terminator == "-->" ? 4 : 0
        end

        # All quantifiers are possessive and the bare-part class
        # excludes "/" and ">": the possessive groups can never consume
        # the closing delimiter, so no backtracking is possible and the
        # match is linear even on malformed tags.
        EMPTY_ELEMENT_RE = %r{<([A-Za-z_][\w.:-]*+)((?:"[^"]*+"|'[^']*+'|[^<>"'/]++)*+)/>}

        def normalize_markup(markup, needs_apos, needs_expand)
          markup = markup.gsub("&apos;", "'") if needs_apos
          if needs_expand
            markup = markup.gsub(EMPTY_ELEMENT_RE) do
              "<#{Regexp.last_match(1)}#{Regexp.last_match(2)}></#{Regexp.last_match(1)}>"
            end
          end
          markup
        end

        # Documents compose from their parts: the native serializer
        # only walks the root subtree, so declaration, DOCTYPE, PIs and
        # document-level text are assembled around it explicitly.
        def serialize_document(doc, options)
          # Nokogiri's document shape: every top-level part is
          # newline-terminated, at any indent — declaration, DOCTYPE,
          # document PIs, the root element, trailing newline after it.
          # Document-level text is content, not structure: no added
          # newline.
          parts = []

          include_decl = !options[:no_declaration] && options.fetch(:declaration) do
            document_has_declaration?(doc)
          end
          if include_decl
            declaration = attachments.get(doc, :declaration)
            parts << (declaration ? declaration.to_xml : default_declaration_xml(doc, options)) << "\n"
          end

          doctype = attachments.get(doc, :doctype)
          parts << doctype.to_xml << "\n" if doctype

          native = native_doctype_xml(doc)
          parts << native << "\n" if native

          if DOC_NODE_SUPPORTED
            # The libxml2-model document node: prolog PIs/comments,
            # the root, epilog PIs/comments — in document order, so
            # epilog parts serialize after the root (issue #130).
            doc_children = document_node_children(doc)
            if doc_children
              doc_children.each { |child| parts << raw_serialize(child, options) << "\n" }
            else
              document_pi_nodes(doc).each { |pi| parts << pi.to_xml << "\n" }
              parts << raw_serialize(doc.root, options) << "\n" if doc.root
            end
          else
            document_pi_nodes(doc).each { |pi| parts << pi.to_xml << "\n" }

            parts << raw_serialize(doc.root, options) << "\n" if doc.root
          end

          texts = attachments.get(doc, :document_text)
          texts&.each { |text| parts << XmlEmitter.escape_text(text.content.to_s) }

          parts.join
        end

        def default_declaration_xml(doc, options)
          encoding = options[:encoding] || doc.encoding
          encoding = "UTF-8" if encoding.to_s.empty?
          XmlEmitter.declaration_xml("1.0", encoding, nil)
        end

        def marker_text_for(parent, name)
          return nil unless parent.is_a?(::Leptris::XML::Element)

          marker = "#{Entity::MARKER}#{name};"
          parent.children.to_a.find do |child|
            child.is_a?(::Leptris::XML::Text) && child.content == marker
          end
        end

        def native_doctype_xml(doc)
          dt = doc.doctype
          return nil unless dt

          subset = dt.internal_subset if dt.class.method_defined?(:internal_subset)
          XmlEmitter.doctype_xml(dt.root_name, dt.public_id, dt.system_id, subset)
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

        def document_has_declaration?(native)
          return false unless native.is_a?(::Leptris::XML::Document)

          return true if attachments.get(native, :declaration)

          attachments.get(native, :had_source_declaration) ? true : false
        end

        # Document-level PI pseudo-nodes, materialized once from the C
        # list and cached per document: children and serialization read
        # the same objects, so wrapper mutations round-trip. Build the
        # cache BEFORE appending a PI with add_pi, or the C-side
        # addition would be double-counted.
        # The document node's children, or nil when the node does not
        # reflect reality: parsed documents always list the root
        # element among their children, but programmatically built
        # ones do not (binding gap) — those keep the legacy parts
        # path.
        def document_node_children(doc)
          doc_children = doc.children.to_a
          has_root = doc_children.any?(::Leptris::XML::Element)
          return doc_children if has_root
          return doc_children if doc.root.nil?

          nil
        end

        def document_pi_nodes(doc)
          attachments.get(doc, :doc_pi_nodes) || begin
            nodes = doc.processing_instructions.map do |(target, data)|
              CustomizedLeptris::DocumentPI.new(target, data, doc)
            end
            attachments.set(doc, :doc_pi_nodes, nodes)
            nodes
          end
        end

        def assemble_document_children(doc)
          children = []

          native_doctype = doc.doctype
          children << native_doctype if native_doctype

          doctype_wrapper = attachments.get(doc, :doctype)
          children << doctype_wrapper if doctype_wrapper

          if DOC_NODE_SUPPORTED
            # The libxml2-model document node lists prolog PIs/comments,
            # the root, and epilog PIs/comments in document order —
            # the Nokogiri-shaped contract, epilog anchoring included
            # (issue #130). Built (programmatic) documents are not yet
            # fully reflected by the node (binding gap: an attached
            # root does not appear); document_node_children answers
            # nil there for the legacy parts path.
            doc_children = document_node_children(doc)
            if doc_children
              children.concat(doc_children)
            else
              children.concat(document_pi_nodes(doc))
              children << doc.root if doc.root
            end
          else
            # Legacy path: document-level PIs live outside the element
            # tree in a flat pre-root list (libleptris < 1.9.7 C
            # model); epilog anchoring is not representable there.
            children.concat(document_pi_nodes(doc))

            children << doc.root if doc.root
          end

          texts = attachments.get(doc, :document_text)
          children.concat(texts) if texts
          children
        end

        def add_document_child(doc, child)
          case child
          when CustomizedLeptris::Declaration
            child.parent_doc = doc
            attachments.set(doc, :declaration, child)
          when CustomizedLeptris::Doctype
            child.parent_doc = doc
            attachments.set(doc, :doctype, child)
          when ::Leptris::XML::DocType
            raise Moxml::DocumentStructureError.new(
              "libleptris does not support attaching a native DocType to a document",
            )
          when ::Leptris::XML::Element
            doc.root = child
          when ::Leptris::XML::ProcessingInstruction
            document_pi_nodes(doc)
            doc.add_pi(child.target, child.content.to_s)
            document_pi_nodes(doc) << CustomizedLeptris::DocumentPI.new(
              child.target, child.content.to_s, doc
            )
          when CustomizedLeptris::DocumentPI
            document_pi_nodes(doc)
            doc.add_pi(child.target, child.data)
            document_pi_nodes(doc) << child
          when ::Leptris::XML::Text
            texts = attachments.get(doc, :document_text) || []
            texts << child
            attachments.set(doc, :document_text, texts)
            child
          else
            raise Moxml::DocumentStructureError.new(
              "Unsupported document child: #{child.class}",
            )
          end
          child
        end
      end

      # Bridge between the leptris SAX callbacks and Moxml::SAX::Handler.
      #
      # @private
      class LeptrisSAXBridge < ::Leptris::XML::SAX::Document
        include Moxml::SAX::NamespaceSplitter

        def initialize(handler)
          @handler = handler
          super()
        end

        def start_document
          @handler.on_start_document
        end

        def end_document
          @handler.on_end_document
        end

        def start_element(name, attrs = [])
          attr_hash, ns_hash = split_attributes_and_namespaces(attrs)
          @handler.on_start_element(name, attr_hash, ns_hash)
        end

        def end_element(name)
          @handler.on_end_element(name)
        end

        def characters(string)
          @handler.on_characters(string)
        end

        def comment(string)
          @handler.on_comment(string)
        end

        def cdata_block(string)
          @handler.on_cdata(string)
        end

        def processing_instruction(name, content)
          @handler.on_processing_instruction(name, content || "")
        end

        def error(message, _line = 0, _column = 0)
          @handler.on_error(Moxml::ParseError.new(message))
        end
      end
    end
  end
end
