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
      class << self
        def attachments
          @attachments ||= Moxml::NativeAttachment.new
        end

        def set_root(doc, element)
          doc.root = element
        end

        def parse(xml, options = {}, _context = nil)
          xml_string = xml.is_a?(IO) || xml.is_a?(StringIO) ? xml.read : xml.to_s
          processed = preprocess_entities(xml_string)

          native_doc = begin
            ::Leptris::XML::Document.parse(processed)
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

          doc
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
          case node
          when ::Leptris::XML::Document then :document
          when ::Leptris::XML::DocType, CustomizedLeptris::Doctype then :doctype
          when CustomizedLeptris::Declaration then :declaration
          when CustomizedLeptris::EntityReference then :entity_reference
          when ::Leptris::XML::CDATA then :cdata
          when ::Leptris::XML::Comment then :comment
          when ::Leptris::XML::ProcessingInstruction then :processing_instruction
          when ::Leptris::XML::Text, CustomizedLeptris::TextSegment then :text
          when ::Leptris::XML::Element then :element
          when ::Leptris::XML::Attr then :attribute
          else :unknown
          end
        end

        def node_name(node)
          return node.root_name if node.is_a?(::Leptris::XML::DocType)

          node.name.to_s.dup.force_encoding("UTF-8")
        end

        def set_node_name(node, name)
          case node
          when ::Leptris::XML::ProcessingInstruction then node.target = name
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
          else
            node.dup
          end
        end

        def children(node)
          case node
          when ::Leptris::XML::Document
            assemble_document_children(node)
          when CustomizedLeptris::Declaration, CustomizedLeptris::Doctype,
               CustomizedLeptris::EntityReference, CustomizedLeptris::TextSegment
            []
          else
            split_entity_markers(node.children.to_a, node)
          end
        end

        # Expand marker-bearing text nodes into the child sequence the
        # moxml contract exposes: text, EntityReference, text, ...
        def split_entity_markers(natives, parent)
          result = []
          natives.each do |child|
            content = child.content.to_s.dup.force_encoding("UTF-8") if child.is_a?(::Leptris::XML::Text)
            if content&.include?(Base::ENTITY_MARKER)
              content.scan(/([^#{Base::ENTITY_MARKER}]*)(?:#{Base::ENTITY_MARKER}([\w.:-]+);)?/o) do
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
          when CustomizedLeptris::Declaration, CustomizedLeptris::Doctype then node.parent_doc
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

        def add_child(parent, child)
          case parent
          when ::Leptris::XML::Document then add_document_child(parent, child)
          else
            if child.is_a?(CustomizedLeptris::EntityReference)
              marker = parent.document.create_text_node("#{Base::ENTITY_MARKER}#{child.name};")
              parent.add_child(marker)
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

        # XPath is evaluated by Moxml's pure-Ruby XPath engine rather
        # than libleptris's native engine: the native engine does not
        # resolve expression prefixes against document-declared
        # namespaces, which Moxml's cross-adapter consistency contract
        # requires. Same trade-off HeadedOx makes over Ox.
        def xpath(node, expression, namespaces = {})
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

        def at_xpath(node, expression, namespaces = {})
          xpath(node, expression, namespaces).first
        end

        def serialize(node, options = {})
          xml = raw_serialize(node, options)
          xml = restore_entities(xml)
          normalize_serialization(xml, options)
        end

        def raw_serialize(node, options)
          # CDATA must precede Text in this chain: CDATA < Text in the
          # binding, so a Text branch first would swallow CDATA nodes.
          case node
          when CustomizedLeptris::Declaration, CustomizedLeptris::Doctype,
               CustomizedLeptris::EntityReference
            return node.to_xml
          when ::Leptris::XML::CDATA
            return "<![CDATA[#{node.content.to_s.gsub(']]>', ']]]]><![CDATA[>')}]]>"
          when ::Leptris::XML::Comment
            return "<!--#{node.content}-->"
          when ::Leptris::XML::ProcessingInstruction
            content = node.content.to_s
            return content.empty? ? "<?#{node.target}?>" : "<?#{node.target} #{content}?>"
          when ::Leptris::XML::Text, CustomizedLeptris::TextSegment
            return escape_text(node.content.to_s)
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
          parts = []

          include_decl = !options[:no_declaration] && options.fetch(:declaration) do
            document_has_declaration?(doc)
          end
          if include_decl
            declaration = attachments.get(doc, :declaration)
            parts << (declaration ? declaration.to_xml : default_declaration_xml(doc, options))
          end

          doctype = attachments.get(doc, :doctype)
          parts << doctype.to_xml if doctype

          native = native_doctype_xml(doc)
          parts << native if native

          (doc.processing_instructions || []).each do |(target, data)|
            parts << (data.to_s.empty? ? "<?#{target}?>" : "<?#{target} #{data}?>")
          end

          parts << raw_serialize(doc.root, options) if doc.root

          texts = attachments.get(doc, :document_text)
          texts&.each { |text| parts << escape_text(text.content.to_s) }

          parts.join
        end

        # moxml text canonical form: only & < > are escaped; quotes
        # stay literal in content.
        def escape_text(text)
          text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
        end

        def default_declaration_xml(doc, options)
          encoding = options[:encoding] || doc.encoding
          encoding = "UTF-8" if encoding.to_s.empty?
          %(<?xml version="1.0" encoding="#{encoding}"?>)
        end

        def marker_text_for(parent, name)
          return nil unless parent.is_a?(::Leptris::XML::Element)

          marker = "#{Base::ENTITY_MARKER}#{name};"
          parent.children.to_a.find do |child|
            child.is_a?(::Leptris::XML::Text) && child.content == marker
          end
        end

        def native_doctype_xml(doc)
          dt = doc.doctype
          return nil unless dt

          output = "<!DOCTYPE #{dt.root_name}"
          if dt.public_id && !dt.public_id.empty?
            output += %( PUBLIC "#{dt.public_id}")
            output += %( "#{dt.system_id}") if dt.system_id
          elsif dt.system_id && !dt.system_id.to_s.empty?
            output += %( SYSTEM "#{dt.system_id}")
          end
          "#{output}>"
        end

        def entity_refs?(element)
          element.is_a?(::Leptris::XML::Element) &&
            !attachments.get(element, :entity_refs).to_a.empty?
        end

        # Registry-based entity references are not in the native tree,
        # so the native serializer cannot see them; compose the element
        # from the wrapper-visible children instead.
        def serialize_entity_bearing_element(element, options)
          name = element.prefix ? "#{element.prefix}:#{element.name}" : element.name
          attrs = element.attribute_nodes.map do |attr|
            %( #{attr.name}="#{attr.value.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')}")
          end.join
          decls = element.namespace_definitions.map do |ns|
            ns.prefix ? %( xmlns:#{ns.prefix}="#{ns.href}") : %( xmlns="#{ns.href}")
          end.join
          inner = children(element).map { |child| raw_serialize(child, options) }.join
          "<#{name}#{decls}#{attrs}>#{inner}</#{name}>"
        end

        def sax_parse(xml, handler)
          bridge = LeptrisSAXBridge.new(handler)
          xml_string = xml.is_a?(IO) || xml.is_a?(::StringIO) ? xml.read : xml.to_s
          ::Leptris::XML::SAX::Parser.new(bridge).parse(xml_string)
        rescue ::Leptris::XML::ParseError, ::Leptris::XML::Error => e
          handler.on_error(Moxml::ParseError.new(e.message))
        end

        private

        def record_source_declaration(native_doc, xml_string)
          had = xml_string.match?(/\A\s*<\?xml\b/)
          attachments.set(native_doc, :had_source_declaration, had)
        end

        def document_has_declaration?(native)
          return false unless native.is_a?(::Leptris::XML::Document)

          return true if attachments.get(native, :declaration)

          attachments.get(native, :had_source_declaration) ? true : false
        end

        def assemble_document_children(doc)
          children = []

          native_doctype = doc.doctype
          children << native_doctype if native_doctype

          doctype_wrapper = attachments.get(doc, :doctype)
          children << doctype_wrapper if doctype_wrapper

          children << doc.root if doc.root

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
            doc.add_pi(child.target, child.content.to_s)
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
