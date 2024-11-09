# lib/moxml/xml_utils.rb
module Moxml
  module XmlUtils
    def encode_entities(text, attr = false)
      text.to_s.gsub(/[&<>'"]/) do |match|
        case match
        when "&" then "&amp;"
        when "<" then "&lt;"
        when ">" then "&gt;"
        when "'" then attr ? "&apos;" : "'"
        when '"' then attr ? "&quot;" : '"'
        end
      end
    end

    def validate_name(name)
      unless name.is_a?(String) && name.match?(/^[a-zA-Z_][\w\-\.:]*$/)
        raise ValidationError, "Invalid XML name: #{name}"
      end
    end

    def validate_uri(uri)
      unless uri.empty? || uri.match?(/\A[a-zA-Z][a-zA-Z0-9+\-.]*:|#\w+\z/)
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
