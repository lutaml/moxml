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

        def set_namespace(_element, _ns)
          # libleptris resolves namespaces from declarations on the
          # tree itself; there is no separate node-to-namespace link
          # to maintain.
        end

        def namespace(element)
          element.namespace
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
          when ::Leptris::XML::Text then :text
          when ::Leptris::XML::Element then :element
          when ::Leptris::XML::Attr then :attribute
          else :unknown
          end
        end

        def node_name(node)
          case node
          when CustomizedLeptris::Doctype then node.name
          when ::Leptris::XML::DocType then node.root_name
          else node.name
          end
        end

        def set_node_name(node, name)
          case node
          when CustomizedLeptris::Doctype then node.name = name
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
               CustomizedLeptris::EntityReference
            []
          else
            node.children.to_a
          end
        end

        def parent(node)
          case node
          when ::Leptris::XML::Document then nil
          when CustomizedLeptris::Declaration, CustomizedLeptris::Doctype then node.parent_doc
          when CustomizedLeptris::EntityReference then node.parent
          else node.parent
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
          attr.name
        end

        def set_attribute(element, name, value)
          element[name.to_s] = value.to_s
        end

        def set_attribute_name(attr, name)
          # Attr is an immutable value object; renames go through the element.
          element = attr.element
          value = attr.value
          element.remove_attribute(attr.name)
          element[name.to_s] = value
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
            child = parent.document.create_text_node(child) if child.is_a?(String)
            parent.add_child(child)
          end
        end

        def add_previous_sibling(node, new_node)
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
          raise Moxml::DocumentStructureError.new(
            "cannot replace a detached node",
          ) unless parent

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
          else node.content.to_s
          end
        end

        def inner_text(node)
          node.inner_text
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

        def namespace_prefix(ns)
          ns.prefix
        end

        def namespace_uri(ns)
          ns.href
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
            seen = {}
            nodes.map { |n| n.is_a?(Moxml::Node) ? n.native : n }
                .select do |native|
                  if seen[native.object_id]
                    false
                  else
                    seen[native.object_id] = true
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
          case node
          when CustomizedLeptris::Declaration, CustomizedLeptris::Doctype,
               CustomizedLeptris::EntityReference
            return node.to_xml
          when ::Leptris::XML::Text
            return encode_entities(node.content.to_s)
          when ::Leptris::XML::Comment
            return "<!--#{node.content}-->"
          when ::Leptris::XML::CDATA
            return "<![CDATA[#{node.content.to_s.gsub("]]>", "]]]]><![CDATA[>")}]]>"
          when ::Leptris::XML::ProcessingInstruction
            content = node.content.to_s
            return content.empty? ? "<?#{node.target}?>" : "<?#{node.target} #{content}?>"
          end

          include_decl = options.fetch(:declaration) do
            options[:no_declaration] ? false : document_has_declaration?(node)
          end
          xml = node.to_xml(
            indent: options.fetch(:indent, 0),
            no_decl: !include_decl,
            encoding: options[:encoding],
          )
          restore_entities(xml)
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
            raise Moxml::NotImplementedError.new(
              "libleptris does not support document-level processing instructions",
              feature: "document PI",
            )
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
