# rubocop:disable Style/FrozenStringLiteralComment

require "oga"

# monkey patch the Oga generator because it's not configurable
# https://github.com/yorickpeterse/oga/blob/main/lib/oga/xml/generator.rb
module Moxml
  module Adapter
    module CustomizedOga
      class XmlGenerator < ::Oga::XML::Generator
        def self_closing?(_element)
          # Always expand tags
          false
        end

        def on_element(element, output)
          name = element.expanded_name

          attrs = []
          element.attributes.each do |attr|
            attrs << " "
            on_attribute(attr, attrs)
          end

          closing_tag = if self_closing?(element)
                          html_void_element?(element) ? ">" : " />"
                        else
                          ">"
                        end

          output << "<#{name}#{attrs.join}#{closing_tag}"
        end

        def on_namespace_definition(ns, output)
          name = "xmlns"
          name += ":#{ns.name}" unless ns.name.nil?

          output << %(#{name}="#{ns.uri}")
        end

        def on_attribute(attr, output)
          return super unless attr.value&.include?("'")

          output << %(#{attr.expanded_name}="#{encode(attr.value)}")
        end

        def on_cdata(node, output)
          # Split any embedded end sequence into adjacent sections
          return super unless node.text.include?("]]>")

          output << ::Moxml::XmlEmitter.cdata(node.text)
        end

        def on_processing_instruction(node, output)
          # put the space between the name and text
          output << "<?#{node.name} #{node.text}?>"
        end

        def on_xml_declaration(node, output)
          super
          # remove the space before the closing tag
          output.gsub!(/ \?>$/, "?>")
        end

        protected

        def encode(input)
          # moxml-canonical attribute form: apostrophes stay literal
          ::Moxml::XmlEmitter.escape_attribute(input.to_s)
        end
      end
    end
  end
end
