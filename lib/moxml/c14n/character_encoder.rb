# frozen_string_literal: true

module Moxml
  module C14n
    # Character encoder for C14N output. Handles the entity escaping
    # mandated by W3C C14N 1.0 §2.4 / 1.1 §2.4 for text and attribute values.
    class CharacterEncoder
      TEXT_ESCAPES = {
        "&" => "&amp;",
        "<" => "&lt;",
        ">" => "&gt;",
        "\r" => "&#xD;",
      }.freeze
      ATTRIBUTE_ESCAPES = TEXT_ESCAPES.merge(
        '"' => "&quot;",
        "\t" => "&#x9;",
        "\n" => "&#xA;",
      ).freeze

      def encode_text(text)
        text.to_s.gsub(/[&<>\r]/, TEXT_ESCAPES)
      end

      def encode_attribute(value)
        value.to_s.gsub(/[&<"\t\n\r]/, ATTRIBUTE_ESCAPES)
      end
    end
  end
end
