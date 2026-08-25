# frozen_string_literal: true

require "oga"

module Moxml
  module Adapter
    class Oga < Base
      # Trigger autoloads that prepend override modules onto Oga's
      # native classes before any parse / read runs.
      # - EntityDecoderOverride: replace Oga 3.4's multi-pass decoder
      #   with a single-pass decoder on Oga::EntityDecoder.
      # - RawValueOverride: route Attribute#value / Text#text through
      #   the NativeAttachment sidecar so user-authored values bypass
      #   the lazy decoder and are returned verbatim.
      ::Moxml::Adapter::CustomizedOga::EntityDecoderOverride
      ::Moxml::Adapter::CustomizedOga::RawValueOverride

      class << self
        def attachments
          @attachments ||= Moxml::NativeAttachment.new
        end

        def set_root(doc, element)
          # Clear existing root element if any - Oga's NodeSet needs special handling
          # We need to manually remove elements since NodeSet doesn't support clear or delete_if
          elements_to_remove = doc.children.grep(::Oga::XML::Element)
          elements_to_remove.each { |elem| doc.children.delete(elem) }
          doc.children << element
        end

        def parse(xml, options = {}, _context = nil)
          processed_xml = preprocess_entities(xml)

          native_doc = begin
            ::Oga.parse_xml(processed_xml, strict: options[:strict])
          rescue LL::ParserError => e
            raise Moxml::ParseError.new(
              e.message,
              source: xml.is_a?(String) ? xml[0..100] : nil,
            )
          end

          ctx = _context || Context.new(:oga)
          DocumentBuilder.new(ctx).build(native_doc)
        end

        # SAX parsing implementation for Oga.
        #
        # Driven off `Oga.parse_xml` plus a DOM walk because Oga 3.4's
        # native SAX parser decodes `on_text` content before delivery and
        # exposes no hook to override. The prepended EntityDecoderOverride
        # ensures `node.text` invoked during the walk produces the correct
        # single-pass decode, so no separate entity pass is needed here.
        # Trade-off: peak memory scales with document size (Oga 3.4 is the
        # final release of an unmaintained gem; the trade is accepted).
        #
        # @param xml [String, IO] XML to parse
        # @param handler [Moxml::SAX::Handler] Moxml SAX handler
        # @return [void]
        def sax_parse(xml, handler)
          xml_string = xml.is_a?(IO) || xml.is_a?(StringIO) ? xml.read : xml.to_s
          native_doc = ::Oga.parse_xml(xml_string)

          bridge = OgaSAXBridge.new(handler)
          bridge.on_start_document
          native_doc.children.each { |child| bridge.emit(child) }
          bridge.on_end_document
        rescue StandardError => e
          handler.on_error(Moxml::ParseError.new(e.message))
        end

        def create_document(_native_doc = nil)
          ::Oga::XML::Document.new
        end

        def create_native_element(name, _owner_doc = nil)
          ::Oga::XML::Element.new(name: name)
        end

        def create_native_text(content, _owner_doc = nil)
          processed = preprocess_entities(content)
          text = ::Oga::XML::Text.new(text: processed)
          # Oga::XML::Text.new stores the value via ivar, bypassing the
          # RawValueOverride setter. Set the sidecar explicitly so reads
          # return the user-supplied value verbatim rather than running
          # it through the lazy decoder.
          attachments.set(text, :raw_text, processed)
          text
        end

        def create_native_entity_reference(name)
          text = ::Oga::XML::Text.new
          text.text = "#{self::ENTITY_MARKER}#{name};"
          attachments.set(text, :entity_name, name)
          text
        end

        def entity_reference_name(node)
          attachments.get(node, :entity_name)
        end

        def create_native_cdata(content, _owner_doc = nil)
          ::Oga::XML::Cdata.new(text: content)
        end

        def create_native_comment(content, _owner_doc = nil)
          ::Oga::XML::Comment.new(text: content)
        end

        def create_native_doctype(name, external_id, system_id)
          ::Oga::XML::Doctype.new(
            name: name, public_id: external_id, system_id: system_id,
            type: external_id ? "PUBLIC" : "SYSTEM"
          )
        end

        def create_native_processing_instruction(target, content)
          ::Oga::XML::ProcessingInstruction.new(name: target, text: content)
        end

        def create_native_declaration(version, encoding, standalone)
          attrs = {
            version: version,
            encoding: encoding,
            standalone: standalone,
          }.compact
          ::Moxml::Adapter::CustomizedOga::XmlDeclaration.new(attrs)
        end

        def declaration_attribute(declaration, attr_name)
          unless ::Moxml::Declaration::ALLOWED_ATTRIBUTES.include?(attr_name.to_s)
            return
          end

          declaration.public_send(attr_name)
        end

        def set_declaration_attribute(declaration, attr_name, value)
          unless ::Moxml::Declaration::ALLOWED_ATTRIBUTES.include?(attr_name.to_s)
            return
          end

          declaration.public_send("#{attr_name}=", value)
        end

        def create_native_namespace(element, prefix, uri)
          ns = element.available_namespaces[prefix]
          return ns unless ns.nil?

          # Oga creates an attribute and registers a namespace
          set_attribute(element,
                        [::Oga::XML::Element::XMLNS_PREFIX, prefix].compact.join(":"), uri)
          element.register_namespace(prefix, uri)
          ::Oga::XML::Namespace.new(name: prefix, uri: uri)
        end

        def set_namespace(element, ns_or_string)
          element.namespace_name = ns_or_string.to_s
          element
        end

        def namespace(element)
          case element
          when ::Oga::XML::Element, ::Oga::XML::Attribute
            element.namespace
          end
        rescue NoMethodError
          # Oga attributes fail with NoMethodError:
          # undefined method `available_namespaces' for nil:NilClass
          nil
        end

        def processing_instruction_target(node)
          node.name
        end

        def node_type(node)
          case node
          when ::Oga::XML::Element then :element
          when ::Oga::XML::Text
            if attachments.key?(node, :entity_name)
              :entity_reference
            else
              :text
            end
          when ::Oga::XML::Cdata then :cdata
          when ::Oga::XML::Comment then :comment
          when ::Oga::XML::Attribute then :attribute
          when ::Oga::XML::Namespace then :namespace
          when ::Oga::XML::ProcessingInstruction then :processing_instruction
          when ::Oga::XML::Document then :document
          when ::Oga::XML::Doctype then :doctype
          else :unknown
          end
        end

        def node_name(node)
          node.name
        end

        def set_node_name(node, name)
          node.name = name
        end

        def children(node)
          all_children = []

          if node.is_a?(::Oga::XML::Document)
            all_children += [node.xml_declaration,
                             node.doctype].compact
          end

          return all_children unless node.is_a?(::Oga::XML::Node) || node.is_a?(::Oga::XML::Document)

          child_nodes = node.children.to_a
          # Filter out whitespace-only text nodes at document level only.
          # Document-level whitespace (between <?xml?> and <root>) is
          # formatting, not content, and differs across adapters.
          # Whitespace inside elements (e.g. "FigureA.1" spacing) is
          # meaningful and must be preserved.
          if node.is_a?(::Oga::XML::Document)
            child_nodes = child_nodes.reject do |child|
              child.is_a?(::Oga::XML::Text) && child.text.strip.empty?
            end
          end
          all_children + child_nodes
        end

        def adjacent_to_entity_reference?(node)
          entity_ref?(node.previous) || entity_ref?(node.next)
        end

        def entity_ref?(node)
          node.is_a?(::Oga::XML::Text) &&
            attachments.get(node, :entity_name)
        end

        def parent(node)
          node.parent if node.is_a?(::Oga::XML::Node)
        end

        def next_sibling(node)
          node.next
        end

        def previous_sibling(node)
          node.previous
        end

        def document(node)
          current = node
          current = current.parent while parent(current)

          current
        end

        def root(document)
          document.children.find { |node| node.is_a?(::Oga::XML::Element) }
        end

        def attribute_element(attr)
          attr.element
        end

        def attributes(element)
          return [] unless element.is_a?(::Oga::XML::Element)

          # remove attributes-namespaces
          element.attributes.reject do |attr|
            attr.name == ::Oga::XML::Element::XMLNS_PREFIX || attr.namespace_name == ::Oga::XML::Element::XMLNS_PREFIX
          end
        end

        def set_attribute(element, name, value)
          namespace_name = nil
          if name.to_s.include?(":")
            namespace_name, name = name.to_s.split(":",
                                                   2)
          end

          processed = preprocess_entities(value.to_s)
          attr = ::Oga::XML::Attribute.new(
            name: name.to_s,
            namespace_name: namespace_name,
            value: processed,
          )
          # See create_native_text: Attribute.new bypasses the override
          # setter, so populate the sidecar here.
          attachments.set(attr, :raw_value, processed)
          element.add_attribute(attr)
        end

        def get_attribute(element, name)
          element.attribute(name.to_s)
        end

        def get_attribute_value(element, name)
          attr = element.attribute(name.to_s)
          attr&.value
        end

        def remove_attribute(element, name)
          attr = element.attribute(name.to_s)
          element.attributes.delete(attr) if attr
        end

        def add_child(element, child_or_text)
          child =
            if child_or_text.is_a?(String)
              create_native_text(child_or_text)
            else
              child_or_text
            end

          if element.is_a?(::Oga::XML::Document) &&
              child.is_a?(::Oga::XML::XmlDeclaration)
            attachments.set(element, :xml_declaration, child)
            return
          end

          # Insert doctype before root element in document
          if element.is_a?(::Oga::XML::Document) && child.is_a?(::Oga::XML::Doctype)
            root_idx = nil
            element.children.each_with_index do |n, i|
              if n.is_a?(::Oga::XML::Element)
                root_idx = i
                break
              end
            end
            if root_idx
              element.children.insert(root_idx, child)
              return
            end
          end

          element.children << child
        end

        def add_previous_sibling(node, sibling)
          if node.parent == sibling.parent
            # Oga doesn't manipulate children of the same parent
            dup_sibling = node.node_set.delete(sibling)
            index = node.node_set.index(node)
            node.node_set.insert(index, dup_sibling)
          else
            node.before(sibling)
          end
        end

        def add_next_sibling(node, sibling)
          if node.parent == sibling.parent
            # Oga doesn't manipulate children of the same parent
            dup_sibling = node.node_set.delete(sibling)
            index = node.node_set.index(node) + 1
            node.node_set.insert(index, dup_sibling)
          else
            node.after(sibling)
          end
        end

        def remove(node)
          # Special handling for declarations on Oga documents
          if node.is_a?(::Oga::XML::XmlDeclaration) &&
              node.parent.is_a?(::Oga::XML::Document)
            # Clear declaration state in attachment map
            attachments.set(node.parent, :xml_declaration, nil)
          end

          node.remove
        end

        def replace(node, new_node)
          node.replace(new_node)
        end

        def replace_children(node, new_children)
          node.children = []
          new_children.each { |child| add_child(node, child) }
        end

        def text_content(node)
          node.text
        end

        def inner_text(node)
          if node.is_a?(::Oga::XML::Element)
            node.inner_text
          else
            node.text
          end
        end

        def set_text_content(node, content)
          processed = preprocess_entities(content)
          if node.is_a?(::Oga::XML::Element)
            node.inner_text = processed
          else
            node.text = processed
          end
        end

        def cdata_content(node)
          node.text
        end

        def set_cdata_content(node, content)
          node.text = content
        end

        def comment_content(node)
          node.text
        end

        def set_comment_content(node, content)
          node.text = content
        end

        def processing_instruction_content(node)
          node.text
        end

        def set_processing_instruction_content(node, content)
          node.text = content
        end

        def namespace_prefix(namespace)
          # nil for the default namespace
          return if namespace.name == ::Oga::XML::Element::XMLNS_PREFIX

          namespace.name
        end

        def namespace_uri(namespace)
          namespace.uri
        end

        def namespace_definitions(node)
          return [] unless node.is_a?(::Oga::XML::Element)

          node.namespaces.values
        end

        # Doctype accessor methods
        # Note: Oga stores SYSTEM identifier in public_id for SYSTEM doctypes.
        # See: Oga::XML::Doctype puts SYSTEM dtd in public_id, system_id is nil.
        def doctype_name(native)
          native.name
        end

        def doctype_external_id(native)
          if native.type == "SYSTEM"
            nil
          else
            native.public_id
          end
        end

        def doctype_system_id(native)
          if native.type == "SYSTEM"
            native.public_id
          else
            native.system_id
          end
        end

        def xpath(node, expression, namespaces = nil)
          node.xpath(expression, {},
                     namespaces: namespaces&.transform_keys(&:to_s)).to_a
        rescue ::LL::ParserError => e
          raise Moxml::XPathError.new(
            e.message,
            expression: expression,
            adapter: "Oga",
            node: node,
          )
        end

        def at_xpath(node, expression, namespaces = nil)
          node.at_xpath(expression, namespaces: namespaces)
        rescue ::Oga::XPath::Error => e
          raise Moxml::XPathError.new(
            e.message,
            expression: expression,
            adapter: "Oga",
            node: node,
          )
        end

        def serialize(node, options = {})
          serialize_without_entity_processing(node, options)
        end

        def has_declaration?(native_doc, _wrapper)
          decl = attachments.get(native_doc, :xml_declaration)
          if decl.nil? && !attachments.key?(native_doc, :xml_declaration)
            native_doc.is_a?(::Oga::XML::Document) && !native_doc.xml_declaration.nil?
          else
            !decl.nil?
          end
        end

        def remove_declaration(native_doc)
          attachments.set(native_doc, :xml_declaration, nil)
        end

        private

        def declaration_to_xml(decl)
          parts = ["<?xml"]
          parts << %( version="#{decl.version}") if decl.version
          parts << %( encoding="#{decl.encoding}") if decl.encoding
          parts << %( standalone="#{decl.standalone}") if decl.standalone
          "#{parts.join}?>"
        end

        def serialize_without_entity_processing(node, options = {})
          if node.is_a?(::Oga::XML::Document)
            effective_xml_declaration = attachments.get(node, :xml_declaration)

            should_include_decl = if options.key?(:no_declaration)
                                    !options[:no_declaration]
                                  elsif options.key?(:declaration)
                                    options[:declaration]
                                  else
                                    effective_xml_declaration || node.xml_declaration ? true : false
                                  end

            output = []

            if should_include_decl
              decl = effective_xml_declaration || node.xml_declaration
              output << if decl
                          declaration_to_xml(decl)
                        else
                          '<?xml version="1.0" encoding="UTF-8"?>'
                        end
              output << "\n"
            end

            if node.doctype
              output << node.doctype.to_xml
              output << "\n"
            end

            node.children.each do |child|
              next if child.is_a?(::Oga::XML::XmlDeclaration)

              output << ::Moxml::Adapter::CustomizedOga::XmlGenerator.new(child).to_xml
            end

            return output.join
          end

          ::Moxml::Adapter::CustomizedOga::XmlGenerator.new(node).to_xml
        end
      end

      # Bridge between a parsed Oga DOM and Moxml SAX events.
      #
      # @private
      class OgaSAXBridge
        include Moxml::SAX::NamespaceSplitter

        def initialize(handler)
          @handler = handler
        end

        def on_start_document
          @handler.on_start_document
        end

        def on_end_document
          @handler.on_end_document
        end

        # Walk a parsed Oga node and emit Moxml SAX events.
        def emit(node)
          case node
          when ::Oga::XML::Element
            element_name = qualified_name(node.namespace_name, node.name)
            pairs = node.attributes.map do |a|
              [qualified_name(a.namespace_name, a.name), a.value]
            end
            attrs, namespaces = split_attributes_and_namespaces(pairs)
            @handler.on_start_element(element_name, attrs, namespaces)
            node.children.each { |c| emit(c) }
            @handler.on_end_element(element_name)
          when ::Oga::XML::Text
            @handler.on_characters(node.text)
          when ::Oga::XML::Cdata
            @handler.on_cdata(node.text)
          when ::Oga::XML::Comment
            @handler.on_comment(node.text)
          when ::Oga::XML::ProcessingInstruction
            @handler.on_processing_instruction(node.name, node.text || "")
          end
        end

        private

        def qualified_name(namespace, local)
          namespace ? "#{namespace}:#{local}" : local
        end
      end
    end
  end
end
