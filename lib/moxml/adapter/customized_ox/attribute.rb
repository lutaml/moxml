# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedOx
      class Attribute < ::Ox::Node
        attr_reader :name, :prefix

        def initialize(attr_name, value, parent = nil)
          self.name = attr_name
          @parent = parent
          @value = value # Explicitly set @value
          super(value)
        end

        def name=(new_name)
          if new_name.to_s.include?(":")
            @prefix, new_name = new_name.to_s.split(":",
                                                    2)
          end

          @name = new_name
        end

        def expanded_name
          [prefix, name].compact.join(":")
        end

        # Expose the value stored in Ox::Node
        # Ox stores attribute values using @value instance variable
        def value
          @value
        end

        # Serialize the attribute to XML format with proper escaping
        def to_xml
          escaped_value = @value.to_s
            .gsub("&", "&amp;")
            .gsub("<", "&lt;")
            .gsub(">", "&gt;")
            .gsub('"', "&quot;")
            .gsub("'", "&apos;")

          "#{expanded_name}=\"#{escaped_value}\""
        end

        # Support string conversion
        def to_s
          to_xml
        end
      end
    end
  end
end
