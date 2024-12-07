# lib/moxml/declaration.rb
module Moxml
  class Declaration < Node
    ALLOWED_VERSIONS = ["1.0", "1.1"].freeze
    ALLOWED_STANDALONE = ["yes", "no"].freeze

    def version
      extract_attribute("version")
    end

    def version=(new_version)
      unless ALLOWED_VERSIONS.include?(new_version)
        raise ValidationError, "Invalid XML version: #{new_version}"
      end
      set_attribute("version", new_version)
    end

    def encoding
      extract_attribute("encoding")
    end

    def encoding=(new_encoding)
      if new_encoding
        begin
          Encoding.find(new_encoding)
        rescue ArgumentError
          raise ValidationError, "Invalid encoding: #{new_encoding}"
        end
      end
      set_attribute("encoding", new_encoding)
    end

    def standalone
      extract_attribute("standalone")
    end

    def standalone=(new_standalone)
      unless new_standalone.nil? || ALLOWED_STANDALONE.include?(new_standalone)
        raise ValidationError, "Invalid standalone value: #{new_standalone}"
      end
      set_attribute("standalone", new_standalone)
    end

    def declaration?
      true
    end

    private

    def extract_attribute(name)
      return nil unless @native.content
      match = @native.content.match(/#{name}="([^"]*)"/)
      match && match[1]
    end

    def set_attribute(name, value)
      attrs = current_attributes
      if value.nil?
        attrs.delete(name)
      else
        attrs[name] = value
      end
      update_content(attrs)
    end

    def current_attributes
      @native.content.to_s.scan(/(\w+)="([^"]*)"/).each_with_object({}) do |(name, value), hash|
        hash[name] = value
      end
    end

    def update_content(attrs)
      @native.native_content = attrs.map { |k, v| %{#{k}="#{v}"} }.join(" ")
    end
  end
end
