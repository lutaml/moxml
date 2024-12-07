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
              ::Nokogiri::XML(xml, nil, options[:encoding]) do |config|
                config.strict.nonet
                config.recover unless options[:strict]
              end
            rescue ::Nokogiri::XML::SyntaxError => e
              raise Moxml::ParseError.new(e.message, line: e.line, column: e.column)
            end

          DocumentBuilder.new(Context.new(:nokogiri)).build(native_doc)
        end

        def create_document
          ::Nokogiri::XML::Document.new
        end

        def create_native_element(name)
          ::Nokogiri::XML::Element.new(name, ::Nokogiri::XML::Document.new)
        end

        def create_native_text(content)
          ::Nokogiri::XML::Text.new(content, ::Nokogiri::XML::Document.new)
        end

        def create_native_cdata(content)
          ::Nokogiri::XML::CDATA.new(::Nokogiri::XML::Document.new, content)
        end

        def create_native_comment(content)
          ::Nokogiri::XML::Comment.new(::Nokogiri::XML::Document.new, content)
        end

        def create_native_processing_instruction(target, content)
          ::Nokogiri::XML::ProcessingInstruction.new(
            ::Nokogiri::XML::Document.new,
            target,
            content
          )
        end

        def create_native_declaration(version, encoding, standalone)
          ::Nokogiri::XML::ProcessingInstruction.new(
            ::Nokogiri::XML::Document.new,
            "xml",
            build_declaration_attrs(version, encoding, standalone)
          )
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
          element.add_namespace(prefix, uri)
        end

        def node_type(node)
          case node
          when ::Nokogiri::XML::Element then :element
          when ::Nokogiri::XML::Text then :text
          when ::Nokogiri::XML::CDATA then :cdata
          when ::Nokogiri::XML::Comment then :comment
          when ::Nokogiri::XML::ProcessingInstruction then :processing_instruction
          when ::Nokogiri::XML::Document then :document
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
          document.root
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
          element.attributes[name.to_s]
        end

        def remove_attribute(element, name)
          element.remove_attribute(name.to_s)
        end

        def add_child(element, child)
          element.add_child(child)
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
          node.content
        end

        def set_text_content(node, content)
          node.content = content
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
          node.content = content
        end

        def processing_instruction_content(node)
          node.content
        end

        def set_processing_instruction_content(node, content)
          node.content = content
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

        def xpath(node, expression, namespaces = {})
          node.xpath(expression, namespaces).to_a
        rescue ::Nokogiri::XML::XPath::SyntaxError => e
          raise Moxml::XPathError, e.message
        end

        def at_xpath(node, expression, namespaces = {})
          node.at_xpath(expression, namespaces)
        rescue ::Nokogiri::XML::XPath::SyntaxError => e
          raise Moxml::XPathError, e.message
        end

        def serialize(node, options = {})
          save_options = ::Nokogiri::XML::Node::SaveOptions::AS_XML

          # Don't force expand empty elements if they're really empty
          save_options |= ::Nokogiri::XML::Node::SaveOptions::NO_EMPTY_TAGS if options[:expand_empty]
          save_options |= ::Nokogiri::XML::Node::SaveOptions::FORMAT if options[:indent].to_i > 0

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
          attrs.map { |k, v| %{#{k}="#{v}"} }.join(" ")
        end
      end
    end
  end
end
