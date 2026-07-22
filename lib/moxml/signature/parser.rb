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
        x509_data_el = at_child(elem, "X509Data")
        key_value_el = at_child(elem, "KeyValue")

        Model::KeyInfo.new(
          id: elem["Id"],
          key_name: key_name_el&.text,
          x509_data: parse_x509_data(x509_data_el),
          key_value: parse_key_value(key_value_el),
          raw_elements: raw_key_info_children(elem),
        )
      end

      def parse_x509_data(elem)
        return nil unless elem

        certificates = at_children(elem, "X509Certificate").map do |cert_el|
          strip_base64(cert_el.text)
        end
        issuer_serial_el = at_child(elem, "X509IssuerSerial")
        subject_name_el = at_child(elem, "X509SubjectName")
        ski_el = at_child(elem, "X509SKI")
        crl_els = at_children(elem, "X509CRL")
        # dsig11:X509Digest is in a different namespace; look it up loosely.
        digest_els = elem.children.select do |c|
          c.is_a?(::Moxml::Element) &&
            c.name == "X509Digest" &&
            c.namespace_uri == DSIG11_NS
        end

        Model::Key::X509Data.new(
          issuer_serial: parse_x509_issuer_serial(issuer_serial_el),
          subject_name: subject_name_el&.text,
          subject_key_id: strip_base64(ski_el&.text),
          certificates: certificates,
          crls: crl_els.map { |e| strip_base64(e.text) },
          digests: digest_els.map { |e| parse_x509_digest(e) },
        )
      end

      def parse_x509_issuer_serial(elem)
        return nil unless elem

        issuer = at_child(elem, "X509IssuerName")
        serial = at_child(elem, "X509SerialNumber")
        return nil unless issuer && serial

        Model::Key::X509IssuerSerial.new(
          issuer_name: issuer.text,
          serial_number: serial.text,
        )
      end

      def parse_x509_digest(elem)
        return nil unless elem

        Model::Key::X509Digest.new(
          algorithm: elem["Algorithm"],
          digest: strip_base64(elem.text),
        )
      end

      def parse_key_value(elem)
        return nil unless elem

        rsa_el = at_child(elem, "RSAKeyValue")
        dsa_el = at_child(elem, "DSAKeyValue")
        ec_el = elem.children.find do |c|
          c.is_a?(::Moxml::Element) &&
            c.name == "ECKeyValue" &&
            c.namespace_uri == DSIG11_NS
        end

        Model::KeyValue.new(
          rsa_key_value: parse_rsa_key_value(rsa_el),
          dsa_key_value: parse_dsa_key_value(dsa_el),
          ec_key_value: parse_ec_key_value(ec_el),
        )
      end

      def parse_rsa_key_value(elem)
        return nil unless elem

        Model::Key::RSAKeyValue.new(
          modulus: text_of(elem, "Modulus"),
          exponent: text_of(elem, "Exponent"),
        )
      end

      def parse_dsa_key_value(elem)
        return nil unless elem

        Model::Key::DSAKeyValue.new(
          p: text_of(elem, "P"),
          q: text_of(elem, "Q"),
          g: text_of(elem, "G"),
          y: text_of(elem, "Y"),
          j: text_of(elem, "J"),
          seed: text_of(elem, "Seed"),
          pgen_counter: text_of(elem, "PgenCounter"),
        )
      end

      def parse_ec_key_value(elem)
        return nil unless elem

        named_curve_el = elem.children.find do |c|
          c.is_a?(::Moxml::Element) &&
            c.name == "NamedCurve" &&
            c.namespace_uri == DSIG11_NS
        end
        public_key_el = elem.children.find do |c|
          c.is_a?(::Moxml::Element) &&
            c.name == "PublicKey" &&
            c.namespace_uri == DSIG11_NS
        end

        Model::Key::ECKeyValue.new(
          named_curve_uri: named_curve_el&.[]("URI"),
          public_key: strip_base64(public_key_el&.text),
        )
      end

      def text_of(parent, local_name)
        elem = at_child(parent, local_name)
        elem&.text
      end

      def strip_base64(text)
        return nil if text.nil?

        text.to_s.gsub(/\s+/, "")
      end

      def raw_key_info_children(elem)
        # Children we don't model explicitly are preserved for round-trip
        # fidelity (PGPData, SPKIData, MgmtData, dsig11:KeyInfoReference,
        # dsig11:DEREncodedKeyValue, xenc:*).
        elem.children.grep(::Moxml::Element).to_a
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
