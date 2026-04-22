# frozen_string_literal: true

require_relative "base"
require_relative "customized_oga"
require "oga"

module Moxml
  module Adapter
    class Oga < Base
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

        def needs_entity_preprocessing?
          true
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

        # SAX parsing implementation for Oga
        #
        # @param xml [String, IO] XML to parse
        # @param handler [Moxml::SAX::Handler] Moxml SAX handler
        # @return [void]
        def sax_parse(xml, handler)
          bridge = OgaSAXBridge.new(handler)

          xml_string = xml.is_a?(IO) || xml.is_a?(StringIO) ? xml.read : xml.to_s

          # Manually call start_document (Oga doesn't)
          handler.on_start_document

          ::Oga.sax_parse_xml(bridge, xml_string)

          # Manually call end_document (Oga doesn't)
          handler.on_end_document
        rescue StandardError => e
          error = Moxml::ParseError.new(e.message)
          handler.on_error(error)
        end

        def create_document(_native_doc = nil)
          ::Oga::XML::Document.new
        end

        def create_native_element(name, _owner_doc = nil)
          ::Oga::XML::Element.new(name: name)
        end

        def create_native_text(content, _owner_doc = nil)
          ::Oga::XML::Text.new(text: preprocess_entities(content))
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

          all_children + node.children.reject do |child|
            child.is_a?(::Oga::XML::Text) &&
              child.text.strip.empty? &&
              !(child.previous.nil? && child.next.nil?) &&
              !adjacent_to_entity_reference?(child)
          end
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

          attr = ::Oga::XML::Attribute.new(
            name: name.to_s,
            namespace_name: namespace_name,
            value: preprocess_entities(value.to_s),
          )
          element.add_attribute(attr)
        end

        def get_attribute(element, name)
          element.attribute(name.to_s)
        end

        def get_attribute_value(element, name)
          element[name.to_s]
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

          # Special handling for declarations on Oga documents
          if element.is_a?(::Oga::XML::Document) &&
              child.is_a?(::Oga::XML::XmlDeclaration)
            # Track declaration state in attachment map
            attachments.set(element, :xml_declaration, child)
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
            # No attachment entry - check native doc (for parsed documents)
            native_doc.respond_to?(:xml_declaration) && !native_doc.xml_declaration.nil?
          else
            !decl.nil?
          end
        end

        private

        def serialize_without_entity_processing(node, options = {})
          # Oga's XmlGenerator doesn't support options directly
          # We need to handle declaration options ourselves for Document nodes
          if node.is_a?(::Oga::XML::Document)
            # Check if we should include declaration
            # Priority: explicit option > existence of xml_declaration (native or attachment)
            effective_xml_declaration = node.xml_declaration || attachments.get(node, :xml_declaration)
            should_include_decl = if options.key?(:no_declaration)
                                    !options[:no_declaration]
                                  elsif options.key?(:declaration)
                                    options[:declaration]
                                  else
                                    # Default: include if document has xml_declaration
                                    effective_xml_declaration ? true : false
                                  end

            # Fix: Check if declaration already exists in children
            # This prevents duplicate declarations when document already has one
            has_existing_declaration = node.children.any?(::Oga::XML::XmlDeclaration)

            if should_include_decl && !effective_xml_declaration && !has_existing_declaration
              # Need to add declaration - create default one
              output = []
              output << '<?xml version="1.0" encoding="UTF-8"?>'
              output << "\n"

              # Serialize doctype if present
              output << node.doctype.to_xml << "\n" if node.doctype

              # Serialize children
              node.children.each do |child|
                output << ::Moxml::Adapter::CustomizedOga::XmlGenerator.new(child).to_xml
              end

              return output.join
            elsif !should_include_decl
              # Skip xml_declaration
              output = []

              # Serialize doctype if present
              output << node.doctype.to_xml << "\n" if node.doctype

              # Serialize root and other children
              node.children.each do |child|
                next if child.is_a?(::Oga::XML::XmlDeclaration)

                output << ::Moxml::Adapter::CustomizedOga::XmlGenerator.new(child).to_xml
              end

              return output.join
            end
          end

          # Default: use XmlGenerator
          # But first check if we need to handle declaration specially
          effective_xml_declaration = node.is_a?(::Oga::XML::Document) && (node.xml_declaration || attachments.get(node, :xml_declaration))
          if node.is_a?(::Oga::XML::Document) && effective_xml_declaration
            # Document has declaration - use custom handling to avoid duplicates
            output = []
            xml_declaration_serialized = false

            # Serialize children, but skip XmlDeclaration if it would cause duplication
            node.children.each do |child|
              xml_declaration = child.is_a?(::Oga::XML::XmlDeclaration)
              next if xml_declaration && xml_declaration_serialized

              xml_declaration_serialized = true if xml_declaration

              output << ::Moxml::Adapter::CustomizedOga::XmlGenerator.new(child).to_xml
            end

            output.join
          else
            # Normal case - use XmlGenerator directly
            ::Moxml::Adapter::CustomizedOga::XmlGenerator.new(node).to_xml
          end
        end
      end
    end

    # Bridge between Oga SAX and Moxml SAX
    #
    # Translates Oga SAX events to Moxml::SAX::Handler events.
    # Oga has different event naming and namespace as first param.
    #
    # @private
    class OgaSAXBridge
      def initialize(handler)
        @handler = handler
      end

      # Oga: on_element(namespace, name, attributes)
      # namespace may be nil
      # attributes is an array of [name, value] pairs
      def on_element(namespace, name, attributes)
        # Build full qualified name if namespace present
        element_name = namespace ? "#{namespace}:#{name}" : name

        # Convert Oga attributes to hash
        attr_hash = {}
        ns_hash = {}

        # Oga delivers attributes as array of [name, value] pairs
        attributes.each do |attr_name, attr_value|
          if attr_name.to_s.start_with?("xmlns")
            prefix = if attr_name.to_s == "xmlns"
                       nil
                     else
                       attr_name.to_s.sub(
                         "xmlns:", ""
                       )
                     end
            ns_hash[prefix] = attr_value
          else
            attr_hash[attr_name.to_s] = attr_value
          end
        end

        @handler.on_start_element(element_name, attr_hash, ns_hash)
      end

      # Oga: after_element(namespace, name)
      def after_element(namespace, name)
        element_name = namespace ? "#{namespace}:#{name}" : name
        @handler.on_end_element(element_name)
      end

      def on_text(text)
        @handler.on_characters(text)
      end

      def on_cdata(text)
        @handler.on_cdata(text)
      end

      def on_comment(text)
        @handler.on_comment(text)
      end

      def on_processing_instruction(name, text)
        @handler.on_processing_instruction(name, text || "")
      end
    end
  end
end
