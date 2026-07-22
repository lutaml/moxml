# frozen_string_literal: true

require "base64"

module Moxml
  module Signature
    # Translates a Moxml::Document containing ds:Signature into a Model::Signature.
    #
    # Robust against namespace prefix variations (ds:, dsig:, default ns).
    class Parser
      DS = { "ds" => DSIG_NS }.freeze

      attr_reader :context

      def initialize(context:)
        @context = context
      end

      # `signature_element`: a Moxml::Element whose name is Signature in the
      # xmldsig# namespace.
      def parse(signature_element)
        Model::Signature.new(
          id: signature_element["Id"],
          signed_info: parse_signed_info(at_child(signature_element, "SignedInfo")),
          signature_value: parse_signature_value(at_child(signature_element, "SignatureValue")),
          key_info: parse_key_info(at_child(signature_element, "KeyInfo")),
          objects: [],
        )
      end

      private

      def parse_signed_info(elem)
        return nil unless elem

        Model::SignedInfo.new(
          id: elem["Id"],
          canonicalization_method: parse_algorithm_method(at_child(elem, "CanonicalizationMethod")),
          signature_method: parse_algorithm_method(at_child(elem, "SignatureMethod")),
          references: at_children(elem, "Reference").map { |r| parse_reference(r) },
        )
      end

      def parse_algorithm_method(elem)
        return nil unless elem

        parameters = {}
        hmac_len = at_child(elem, "HMACOutputLength")
        if hmac_len
          length = begin
            Integer(hmac_len.text.strip)
          rescue StandardError
            nil
          end
          parameters[:hmac_output_length] = length if length
        end

        Model::AlgorithmMethod.new(
          algorithm: elem["Algorithm"],
          parameters: parameters,
        )
      end

      def parse_reference(elem)
        return nil unless elem

        transforms_elem = at_child(elem, "Transforms")
        Model::Reference.new(
          id: elem["Id"],
          uri: elem["URI"],
          type: elem["Type"],
          transforms: parse_transforms(transforms_elem),
          digest_method: parse_digest_method(at_child(elem, "DigestMethod")),
          digest_value: at_child(elem, "DigestValue")&.text || "",
        )
      end

      def parse_transforms(elem)
        return nil unless elem

        transforms = at_children(elem, "Transform").map do |t|
          xpath_children = at_children(t, "XPath").map(&:text)
          Model::Transform.new(
            algorithm: t["Algorithm"],
            parameters: xpath_children.empty? ? {} : { xpaths: xpath_children },
          )
        end
        Model::Transforms.new(transforms: transforms)
      end

      def parse_digest_method(elem)
        return nil unless elem

        Model::DigestMethod.new(algorithm: elem["Algorithm"])
      end

      def parse_signature_value(elem)
        return nil unless elem

        text = (elem.text || "").gsub(/\s+/, "")
        value = text.empty? ? nil : Base64.strict_decode64(text)
        Model::SignatureValue.new(id: elem["Id"], value: value)
      rescue ArgumentError => e
        raise MalformedSignatureError.new(
          "SignatureValue is not valid base64: #{e.message}",
        )
      end

      def parse_key_info(elem)
        return nil unless elem

        key_name_el = at_child(elem, "KeyName")
        Model::KeyInfo.new(
          id: elem["Id"],
          key_name: key_name_el&.text,
        )
      end

      def at_child(parent, local_name)
        parent.children.find do |c|
          c.is_a?(::Moxml::Element) &&
            c.name == local_name &&
            c.namespace_uri == DSIG_NS
        end
      end

      def at_children(parent, local_name)
        parent.children.select do |c|
          c.is_a?(::Moxml::Element) &&
            c.name == local_name &&
            c.namespace_uri == DSIG_NS
        end
      end
    end
  end
end
