# frozen_string_literal: true

require_relative "xml_utils/encoder"

# Ruby 3.3+ requires the URI module to be explicitly required
require "uri" unless defined?(URI)

module Moxml
  module XmlUtils
    def encode_entities(text, mode = nil)
      Encoder.new(text, mode).call
    end

    def validate_declaration_version(version)
      return if ::Moxml::Declaration::ALLOWED_VERSIONS.include?(version)

      raise ValidationError, "Invalid XML version: #{version}"
    end

    def validate_declaration_encoding(encoding)
      return if encoding.nil?

      begin
        Encoding.find(encoding)
      rescue ArgumentError
        raise ValidationError, "Invalid encoding: #{encoding}"
      end
    end

    def validate_declaration_standalone(standalone)
      return if standalone.nil?
      return if ::Moxml::Declaration::ALLOWED_STANDALONE.include?(standalone)

      raise ValidationError, "Invalid standalone value: #{standalone}"
    end

    def validate_comment_content(text)
      if text.start_with?("-") || text.end_with?("-")
        raise ValidationError, "XML comment cannot start or end with a hyphen"
      end

      return unless text.include?("--")

      raise ValidationError, "XML comment cannot contain double hyphens (--)"
    end

    def validate_element_name(name)
      return if name.is_a?(String) && name.match?(/^[a-zA-Z_][\w\-.:]*$/)

      raise ValidationError, "Invalid XML element name: #{name}"
    end

    def validate_pi_target(target)
      return if target.is_a?(String) && target.match?(/^[a-zA-Z_][\w\-.]*$/)

      raise ValidationError,
            "Invalid XML processing instruction target: #{target}"
    end

    def validate_uri(uri, mode: :strict)
      # Empty strings are allowed for default namespace undeclaration (xmlns="").
      return if uri.empty?

      # In lenient mode, accept any string as a namespace URI.
      # Only reject strings containing XML-invalid characters (control characters).
      if mode == :lenient
        if uri.match?(/[\x00-\x08\x0B\x0C\x0E-\x1F]/)
          raise ValidationError, "Invalid URI: #{uri}"
        end

        return
      end

      # Namespace names must be valid URI-references per RFC 3986
      # (W3C Namespaces in XML, https://www.w3.org/TR/xml-names/).
      # Use split instead of parse to avoid scheme-specific validation
      # that rejects valid opaque URIs like "mailto:bar".
      URI::RFC3986_PARSER.split(uri)
    rescue URI::InvalidURIError
      raise ValidationError, "Invalid URI: #{uri}"
    end

    def validate_prefix(prefix)
      return if prefix.match?(/\A[a-zA-Z_][\w-]*\z/)

      raise ValidationError, "Invalid namespace prefix: #{prefix}"
    end

    def normalize_xml_value(value)
      case value
      when nil then ""
      when true then "true"
      when false then "false"
      else value.to_s
      end
    end

    def validate_entity_reference_name(name)
      # Entity names follow the same pattern as element names
      # They must start with a letter or underscore, followed by letters, digits, hyphens, underscores, periods, or colons
      return if name.is_a?(String) && name.match?(/^[a-zA-Z_][\w\-.:]*$/)

      raise ValidationError, "Invalid entity reference name: #{name}"
    end
  end
end
