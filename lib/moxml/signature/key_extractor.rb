# frozen_string_literal: true

require "openssl"
require "base64"

module Moxml
  module Signature
    # Extracts an OpenSSL verification key from a Model::KeyInfo.
    #
    # Strategy (per spec §4.5): X509Certificate is preferred for key
    # reconstruction because it carries the certified binding. Falls back
    # to RSAKeyValue / DSAKeyValue / ECKeyValue if no certificate is
    # present. KeyName is resolved via an application-supplied key map.
    class KeyExtractor
      attr_reader :key_map, :cert_store

      def initialize(key_map: {}, cert_store: nil)
        @key_map = key_map || {}
        @cert_store = cert_store
      end

      def extract(key_info)
        return nil if key_info.nil?

        from_x509_data(key_info.x509_data) ||
          from_key_value(key_info.key_value) ||
          from_key_name(key_info.key_name)
      end

      private

      def from_x509_data(x509_data)
        return nil unless x509_data

        cert_b64 = x509_data.certificates.first
        return nil unless cert_b64

        # Certificates are stored as base64-encoded DER (spec §4.5.4).
        # Decode here so we hand OpenSSL raw DER bytes.
        cert_der = Base64.strict_decode64(cert_b64.to_s.gsub(/\s+/, ""))
        cert = OpenSSL::X509::Certificate.new(cert_der)
        cert.public_key
      rescue OpenSSL::X509::CertificateError, ArgumentError
        nil
      end

      def from_key_value(key_value)
        return nil unless key_value

        if key_value.rsa_key_value
          rsa_public_key(key_value.rsa_key_value)
        elsif key_value.dsa_key_value
          dsa_public_key(key_value.dsa_key_value)
        elsif key_value.ec_key_value
          ec_public_key(key_value.ec_key_value)
        end
      end

      def from_key_name(key_name)
        return nil unless key_name

        key_map[key_name]
      end

      def rsa_public_key(rsa_kv)
        n = crypto_binary_to_integer(rsa_kv.modulus)
        e = crypto_binary_to_integer(rsa_kv.exponent)
        return nil unless n && e

        # OpenSSL 3.x removed RSA.new(n, e). Reconstruct via the
        # SubjectPublicKeyInfo form (PKCS#1 RSA public key DER).
        asn1 = OpenSSL::ASN1::Sequence.new(
          [
            OpenSSL::ASN1::Integer.new(n),
            OpenSSL::ASN1::Integer.new(e),
          ],
        )
        OpenSSL::PKey::RSA.new(asn1.to_der)
      rescue OpenSSL::PKey::RSAError
        nil
      end

      def dsa_public_key(dsa_kv)
        p = crypto_binary_to_integer(dsa_kv.p)
        q = crypto_binary_to_integer(dsa_kv.q)
        g = crypto_binary_to_integer(dsa_kv.g) if dsa_kv.g
        y = crypto_binary_to_integer(dsa_kv.y)
        return nil unless p && q && y

        params = OpenSSL::ASN1::Sequence.new(
          [
            OpenSSL::ASN1::Integer.new(p),
            OpenSSL::ASN1::Integer.new(q),
            OpenSSL::ASN1::Integer.new(g || 0),
            OpenSSL::ASN1::Integer.new(y),
          ],
        )
        OpenSSL::PKey::DSA.new(params.to_der)
      rescue OpenSSL::PKey::DSAError
        nil
      end

      def ec_public_key(ec_kv)
        return nil unless ec_kv.named_curve_uri && ec_kv.public_key

        curve_name = curve_name_for(ec_kv.named_curve_uri)
        return nil unless curve_name

        # The XML signature PublicKey element already contains the
        # uncompressed-point form (0x04 || x || y) per spec §4.5.2.3.
        public_key_decoded = Base64.strict_decode64(ec_kv.public_key)
        spki_der = build_ec_subject_public_key_info(curve_name, public_key_decoded)
        OpenSSL::PKey::EC.new(spki_der)
      rescue OpenSSL::PKey::ECError, ArgumentError
        nil
      end

      # Build a SubjectPublicKeyInfo DER for an EC public key.
      # OpenSSL 3.0 makes PKey instances immutable; we can no longer
      # create an empty EC key and assign public_key=. Constructing the
      # full SPKI and reading it back via OpenSSL::PKey::EC.new(der)
      # is the supported path.
      def build_ec_subject_public_key_info(curve_name, point_octets)
        algorithm = OpenSSL::ASN1::Sequence.new(
          [
            OpenSSL::ASN1::ObjectId.new("id-ecPublicKey"),
            OpenSSL::ASN1::ObjectId.new(curve_name_to_oid(curve_name)),
          ],
        )
        OpenSSL::ASN1::Sequence.new(
          [
            algorithm,
            OpenSSL::ASN1::BitString.new(point_octets),
          ],
        ).to_der
      end

      CURVE_NAME_TO_OID = {
        "prime256v1" => "1.2.840.10045.3.1.7",
        "secp384r1" => "1.3.132.0.34",
        "secp521r1" => "1.3.132.0.35",
      }.freeze
      private_constant :CURVE_NAME_TO_OID

      def curve_name_to_oid(curve_name)
        CURVE_NAME_TO_OID.fetch(curve_name)
      end

      # ds:CryptoBinary is base64-encoded I2OSP output.
      def crypto_binary_to_integer(base64_text)
        return nil unless base64_text

        raw = Base64.strict_decode64(base64_text.to_s.gsub(/\s+/, ""))
        raw.bytes.reduce(0) { |acc, byte| (acc << 8) | byte }
      rescue ArgumentError
        nil
      end

      # Map NamedCurve URN OIDs to OpenSSL curve names (RFC 5480 §2.1).
      CURVE_OID_TO_NAME = {
        "urn:oid:1.2.840.10045.3.1.7" => "prime256v1", # P-256
        "urn:oid:1.3.132.0.34" => "secp384r1",         # P-384
        "urn:oid:1.3.132.0.35" => "secp521r1",         # P-521
      }.freeze
      private_constant :CURVE_OID_TO_NAME

      def curve_name_for(uri)
        CURVE_OID_TO_NAME[uri]
      end
    end
  end
end
