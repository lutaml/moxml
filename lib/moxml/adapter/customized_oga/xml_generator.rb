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

        def on_attribute(attr, output)
          return super unless attr.value&.include?("'")

          output << %Q(#{attr.expanded_name}="#{encode(attr.value)}")
        end
      
        def on_cdata(node, output)
          # Escape the end sequence
          return super unless node.text.include?("]]>")

          chunks = node.text.split("]]>")
          chunks.each_with_index do |chunk, index|
            text = chunk
            text = ">#{text}" unless index.zero?
            text = "#{text}]]" unless index == chunks.length - 1

            output << "<![CDATA[#{text}]]>"
          end

          output
        end

        def on_processing_instruction(node, output)
          # put the space between the name and text
          output << "<?#{node.name} #{node.text}?>"
        end

        def on_xml_declaration(node, output)
          super
          # remove the space before the closing tag
          output.gsub!(/ \?\>$/, '?>')
        end

        protected

        def encode(input)
          # similar to ::Oga::XML::Entities.encode_attribute
          input&.gsub(
            ::Oga::XML::Entities::ENCODE_ATTRIBUTE_REGEXP,
            # Keep apostrophes in attributes
            ::Oga::XML::Entities::ENCODE_ATTRIBUTE_MAPPING.merge("'" => "'")
          )
        end
      end
    end
  end
end
