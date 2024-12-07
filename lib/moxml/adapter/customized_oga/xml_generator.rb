require "oga"

# monkey patch the Oga generator because it's not configurable
module Moxml
  module Adapter
    module CustomizedOga
      class XmlGenerator < ::Oga::XML::Generator
        def self_closing?(_element)
          # Always expand tags
          false
        end

        def on_attribute(attr, output)
          name = attr.expanded_name
          enc_value = attr.value ? encode_attribute(attr.value) : nil

          output << %Q(#{name}="#{enc_value}")
        end

        protected

        def encode_attribute(input)
          input.gsub(
            ::Oga::XML::Entities::ENCODE_ATTRIBUTE_REGEXP,
            # Keep apostrophes in attributes
            ::Oga::XML::Entities::ENCODE_ATTRIBUTE_MAPPING.merge("'" => "'")
          )
        end
      end
    end
  end
end
