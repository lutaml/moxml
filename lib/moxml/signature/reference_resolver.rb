# frozen_string_literal: true

module Moxml
  module Signature
    # Translates a Reference URI to a node (subtree) or octet string ready
    # for the transform pipeline.
    #
    # Only same-document references and bare-octet inputs are handled in
    # this tier. External URI dereferencing is documented in
    # TODO.complete/11.
    class ReferenceResolver
      attr_reader :context, :document

      def initialize(context:, document:)
        @context = context
        @document = document
      end

      # Returns:
      #   - Moxml::Node for same-document references (subtree apex)
      #   - String (octets) for octet inputs
      def resolve(uri)
        case uri.to_s
        when ""
          document.root
        when /\A#/
          resolve_fragment(uri[1..])
        else
          uri.to_s
        end
      end

      private

      def resolve_fragment(fragment)
        case fragment
        when /\Axpointer\(\/\)\z/
          document.root
        when /\Axpointer\(id\(['"]([^'"]+)['"]\)\)\z/
          find_by_id(::Regexp.last_match(1))
        else
          find_by_id(fragment)
        end
      end

      def find_by_id(id)
        candidate = search_by_xml_id(id) || search_by_attribute_id(id)
        unless candidate
          raise MalformedSignatureError.new(
            "Reference URI ##{id.inspect} does not resolve to any element",
          )
        end
        candidate
      end

      def search_by_xml_id(id)
        result = document.at_xpath("//*[@xml:id='#{xpath_escape(id)}']")
        return nil unless result
        return nil unless result.is_a?(::Moxml::Element)

        result
      end

      def search_by_attribute_id(id)
        matches = document
          .xpath("//*[@Id='#{xpath_escape(id)}'] | " \
                 "//*[@ID='#{xpath_escape(id)}']")
          .grep(::Moxml::Element)
        return nil if matches.empty?

        matches.first
      end

      def xpath_escape(value)
        value.to_s.gsub("'", "''")
      end
    end
  end
end
