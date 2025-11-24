# frozen_string_literal: true

require_relative "base"
require "nokogiri"

module Moxml
  module Adapter
    class Nokogiri < Base
      class << self
        def set_root(doc, element)
          doc.root = element
        end

        def parse(xml, options = {})
          native_doc = begin
            if options[:fragment]
              ::Nokogiri::XML::DocumentFragment.parse(xml) do |config|
                config.strict.nonet
                config.recover unless options[:strict]
              end
            else
              ::Nokogiri::XML(xml, nil, options[:encoding]) do |config|
                config.strict.nonet
                config.recover unless options[:strict]
              end
            end
          rescue ::Nokogiri::XML::SyntaxError => e
            raise Moxml::ParseError.new(e.message, line: e.line,
                                                   column: e.column)
          end

          DocumentBuilder.new(Context.new(:nokogiri)).build(native_doc)
        end

        # SAX parsing implementation for Nokogiri
        #
        # @param xml [String, IO] XML to parse
        # @param handler [Moxml::SAX::Handler] Moxml SAX handler
        # @return [void]
        def sax_parse(xml, handler)
          # Create bridge that translates Nokogiri SAX to Moxml SAX
          bridge = NokogiriSAXBridge.new(handler)

          # Create Nokogiri SAX parser
          parser = ::Nokogiri::XML::SAX::Parser.new(bridge)

          # Parse
          if xml.respond_to?(:read)
            parser.parse(xml)
          else
            parser.parse(xml.to_s)
          end
        rescue ::Nokogiri::XML::SyntaxError => e
          error = Moxml::ParseError.new(e.message, line: e.line,
                                                   column: e.column)
          handler.on_error(error)
        end

        def create_document(_native_doc = nil)
          ::Nokogiri::XML::Document.new
        end

        def create_fragment
          # document fragments are weird and should be used with caution:
          # https://github.com/sparklemotion/nokogiri/issues/572
          ::Nokogiri::XML::DocumentFragment.new(
            ::Nokogiri::XML::Document.new,
          )
        end

        def create_native_element(name)
          ::Nokogiri::XML::Element.new(name, create_document)
        end

        def create_native_text(content)
          ::Nokogiri::XML::Text.new(content, create_document)
        end

        def create_native_cdata(content)
          ::Nokogiri::XML::CDATA.new(create_document, content)
        end

        def create_native_comment(content)
          ::Nokogiri::XML::Comment.new(create_document, content)
        end

        def create_native_doctype(name, external_id, system_id)
          create_document.create_internal_subset(
            name, external_id, system_id
          )
        end

        def create_native_processing_instruction(target, content)
          ::Nokogiri::XML::ProcessingInstruction.new(
            ::Nokogiri::XML::Document.new, target, content
          )
        end

        def create_native_declaration(version, encoding, standalone)
          ::Nokogiri::XML::ProcessingInstruction.new(
            create_document,
            "xml",
            build_declaration_attrs(version, encoding, standalone),
          )
        end

        def declaration_attribute(declaration, attr_name)
          return nil unless declaration.content

          match = declaration.content.match(/#{attr_name}="([^"]*)"/)
          match && match[1]
        end

        def set_declaration_attribute(declaration, attr_name, value)
          attrs = current_declaration_attributes(declaration)
          if value.nil?
            attrs.delete(attr_name)
          else
            attrs[attr_name] = value
          end

          declaration.native_content =
            attrs.map { |k, v| %(#{k}="#{v}") }.join(" ")
        end

        def set_namespace(element, ns)
          element.namespace = ns
        end

        def namespace(element)
          element.namespace
        end

        def processing_instruction_target(node)
          node.name
        end

        def create_native_namespace(element, prefix, uri)
          element.add_namespace_definition(prefix, uri)
        end

        def node_type(node)
          case node
          when ::Nokogiri::XML::Element then :element
          when ::Nokogiri::XML::CDATA then :cdata
          when ::Nokogiri::XML::Text then :text
          when ::Nokogiri::XML::Comment then :comment
          when ::Nokogiri::XML::Attr then :attribute
          when ::Nokogiri::XML::Namespace then :namespace
          when ::Nokogiri::XML::ProcessingInstruction then :processing_instruction
          when ::Nokogiri::XML::Document, ::Nokogiri::XML::DocumentFragment then :document
          when ::Nokogiri::XML::DTD then :doctype
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
          node.children.reject do |child|
            child.text? && child.content.strip.empty? &&
              !(child.previous_sibling.nil? && child.next_sibling.nil?)
          end
        end

        def replace_children(node, new_children)
          node.children.unlink
          new_children.each { |child| add_child(node, child) }
        end

        def parent(node)
          node.parent
        end

        def next_sibling(node)
          node.next_sibling
        end

        def previous_sibling(node)
          node.previous_sibling
        end

        def document(node)
          node.document
        end

        def root(document)
          document.respond_to?(:root) ? document.root : document.children.first
        end

        def attribute_element(attr)
          attr.parent
        end

        def attributes(element)
          element.attributes.values
        end

        def set_attribute(element, name, value)
          element[name.to_s] = value.to_s
        end

        def get_attribute(element, name)
          # attributes keys don't include attribute namespaces
          element.attributes[name.to_s]
        end

        def get_attribute_value(element, name)
          # get the attribute value by its name including a namespace
          element[name.to_s]
        end

        def remove_attribute(element, name)
          element.remove_attribute(name.to_s)
        end

        def add_child(element, child)
          if node_type(child) == :doctype
            # avoid exceptions: cannot reparent Nokogiri::XML::DTD there
            element.create_internal_subset(
              child.name, child.external_id, child.system_id
            )
          else
            element.add_child(child)
          end
        end

        def add_previous_sibling(node, sibling)
          node.add_previous_sibling(sibling)
        end

        def add_next_sibling(node, sibling)
          node.add_next_sibling(sibling)
        end

        def remove(node)
          node.remove
        end

        def replace(node, new_node)
          node.replace(new_node)
        end

        def text_content(node)
          node.text
        end

        def inner_text(node)
          text_children = node.children - node.element_children
          text_children.map(&:content).join
        end

        def set_text_content(node, content)
          node.native_content = content
        end

        def cdata_content(node)
          node.content
        end

        def set_cdata_content(node, content)
          node.content = content
        end

        def comment_content(node)
          node.content
        end

        def set_comment_content(node, content)
          node.native_content = content
        end

        def processing_instruction_content(node)
          node.content
        end

        def set_processing_instruction_content(node, content)
          node.native_content = content
        end

        def namespace_prefix(namespace)
          namespace.prefix
        end

        def namespace_uri(namespace)
          namespace.href
        end

        def namespace_definitions(node)
          node.namespace_definitions
        end

        def xpath(node, expression, namespaces = nil)
          node.xpath(expression, namespaces).to_a
        rescue ::Nokogiri::XML::XPath::SyntaxError => e
          raise Moxml::XPathError.new(
            e.message,
            expression: expression,
            adapter: "Nokogiri",
            node: node,
          )
        end

        def at_xpath(node, expression, namespaces = nil)
          node.at_xpath(expression, namespaces)
        rescue ::Nokogiri::XML::XPath::SyntaxError => e
          raise Moxml::XPathError.new(
            e.message,
            expression: expression,
            adapter: "Nokogiri",
            node: node,
          )
        end

        def serialize(node, options = {})
          save_options = ::Nokogiri::XML::Node::SaveOptions::AS_XML

          # Don't force expand empty elements if they're really empty
          if options[:expand_empty]
            save_options |= ::Nokogiri::XML::Node::SaveOptions::NO_EMPTY_TAGS
          end
          if options[:indent].to_i.positive?
            save_options |= ::Nokogiri::XML::Node::SaveOptions::FORMAT
          end
          if options[:no_declaration]
            save_options |= ::Nokogiri::XML::Node::SaveOptions::NO_DECLARATION
          end

          node.to_xml(
            indent: options[:indent],
            encoding: options[:encoding],
            save_with: save_options,
          )
        end

        private

        def build_declaration_attrs(version, encoding, standalone)
          attrs = { "version" => version }
          attrs["encoding"] = encoding if encoding
          attrs["standalone"] = standalone if standalone
          attrs.map { |k, v| %(#{k}="#{v}") }.join(" ")
        end

        def current_declaration_attributes(declaration)
          ::Moxml::Declaration::ALLOWED_ATTRIBUTES.inject({}) do |hsh, attr_name|
            value = declaration_attribute(declaration, attr_name)
            next hsh if value.nil?

            hsh.merge(attr_name => value)
          end
        end
      end

      # Bridge between Nokogiri SAX and Moxml SAX
      #
      # Translates Nokogiri::XML::SAX::Document events to Moxml::SAX::Handler events
      #
      # @private
      class NokogiriSAXBridge < ::Nokogiri::XML::SAX::Document
        def initialize(handler)
          super()
          @handler = handler
        end

        # Map Nokogiri events to Moxml events

        def start_document
          @handler.on_start_document
        end

        def end_document
          @handler.on_end_document
        end

        def start_element(name, attributes = [])
          # Convert Nokogiri attributes array to hash
          attr_hash = {}
          namespaces_hash = {}

          attributes.each do |attr|
            attr_name = attr[0]
            attr_value = attr[1]

            if attr_name.start_with?("xmlns")
              # Namespace declaration
              prefix = attr_name == "xmlns" ? nil : attr_name.sub("xmlns:", "")
              namespaces_hash[prefix] = attr_value
            else
              attr_hash[attr_name] = attr_value
            end
          end

          @handler.on_start_element(name, attr_hash, namespaces_hash)
        end

        def end_element(name)
          @handler.on_end_element(name)
        end

        def characters(string)
          @handler.on_characters(string)
        end

        def cdata_block(string)
          @handler.on_cdata(string)
        end

        def comment(string)
          @handler.on_comment(string)
        end

        def processing_instruction(target, data)
          @handler.on_processing_instruction(target, data || "")
        end

        def error(string)
          @handler.on_error(Moxml::ParseError.new(string))
        end

        def warning(string)
          @handler.on_warning(string)
        end
      end
    end
  end
end
