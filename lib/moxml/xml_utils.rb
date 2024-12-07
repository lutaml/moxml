# lib/moxml/xml_utils.rb
require_relative "xml_utils/encoder"

module Moxml
  module XmlUtils
    def encode_entities(text, mode = nil)
      Encoder.new(text, mode).call
    end

    def validate_name(name)
      unless name.is_a?(String) && name.match?(/^[a-zA-Z_][\w\-\.]*$/)
        raise ValidationError, "Invalid XML name: #{name}"
      end
    end

    def validate_uri(uri)
      unless uri.empty? || uri.match?(/\A#{::URI::DEFAULT_PARSER.make_regexp}\z/)
        raise ValidationError, "Invalid URI: #{uri}"
      end
    end

    def normalize_xml_value(value)
      case value
      when nil then ""
      when true then "true"
      when false then "false"
      else value.to_s
      end
    end
  end
end
