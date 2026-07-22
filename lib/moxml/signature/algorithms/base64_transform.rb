# frozen_string_literal: true

require "base64"

module Moxml
  module Signature
    module Algorithms
      # Base64 decode transform (W3C §6.6.2).
      #
      # Input: octets or nodeset. For nodeset, logically applies self::text(),
      # sorts nodes by document order, concatenates string values, then decodes.
      # Output: octets.
      class Base64Transform < TransformBase
        identifier "http://www.w3.org/2000/09/xmldsig#base64"

        def self.input_type; :octets; end
        def self.output_type; :octets; end

        def transform(input)
          text = input.is_a?(Array) ? input.map { |n| text_of(n) }.join : input.to_s
          stripped = text.gsub(/\s+/, "")
          Base64.strict_decode64(stripped)
        rescue ArgumentError => e
          raise TransformError.new(
            "base64 decode failed: #{e.message}",
            algorithm: self.class.identifier_uri,
          )
        end

        private

        def text_of(node)
          return node.text if node.is_a?(::Moxml::Node)

          node.to_s
        end
      end
    end
  end
end
