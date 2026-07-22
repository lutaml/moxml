# frozen_string_literal: true

require "openssl"

module Moxml
  module Signature
    module Algorithms
      # ECDSA signature methods per FIPS 186-3, bound to a digest.
      #
      # Spec §6.4.3 requires support for ECDSAwithSHA256 over the P-256
      # curve. Recommended: P-384, P-521.
      #
      # The wire format is base64(I2OSP(r, n_bytes) || I2OSP(s, n_bytes))
      # where n_bytes is the byte length of the base point order
      # (32 for P-256, 48 for P-384, 66 for P-521).
      #
      # OpenSSL returns a DER-encoded ASN.1 sequence of (r, s). We convert
      # to the raw r||s form on sign, and back from raw to DER on verify.
      class EcdsaSha < SignatureMethodBase
        PAIRINGS = {
          "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha1" => "SHA1",
          "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha224" => "SHA224",
          "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256" => "SHA256",
          "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha384" => "SHA384",
          "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha512" => "SHA512",
        }.freeze

        # Map OpenSSL curve name → byte length of base point order.
        CURVE_ORDER_BYTES = {
          "prime256v1" => 32,   # P-256
          "secp384r1" => 48,    # P-384
          "secp521r1" => 66,    # P-521 (ceil(521/8) = 66)
        }.freeze

        PAIRINGS.each_key { |uri| identifier uri }

        def initialize(identifier_uri:, parameters: nil)
          super(nil)
          @identifier_uri = identifier_uri
          @parameters = parameters
        end

        def compute_signature(data, key)
          ec_key = coerce_key(key)
          digest_name = self.class::PAIRINGS.fetch(@identifier_uri)
          der_signature = ec_key.sign(digest_name, data)
          der_to_raw(der_signature, coordinate_bytes_for(ec_key))
        end

        def verify_signature(data, key, signature)
          ec_key = coerce_key(key)
          digest_name = self.class::PAIRINGS.fetch(@identifier_uri)
          n_bytes = coordinate_bytes_for(ec_key)
          der_signature = raw_to_der(signature, n_bytes)
          ec_key.verify(digest_name, der_signature, data)
        rescue ArgumentError
          false
        end

        private

        def coerce_key(key)
          case key
          when OpenSSL::PKey::EC then key
          when OpenSSL::PKey::EC::Point
            raise SignatureKeyError,
                  "ECDSA requires an EC key, not a bare Point"
          else
            raise SignatureKeyError,
                  "ECDSA signature method requires OpenSSL::PKey::EC, " \
                  "got #{key.class}"
          end
        end

        def coordinate_bytes_for(ec_key)
          curve_name = ec_key.group.curve_name
          self.class::CURVE_ORDER_BYTES.fetch(curve_name) do
            raise SignatureError,
                  "ECDSA curve #{curve_name.inspect} not supported; " \
                  "add it to EcdsaSha::CURVE_ORDER_BYTES"
          end
        end

        # Convert ASN.1 DER sequence of two INTEGERs to raw r‖s octets.
        def der_to_raw(der, n_bytes)
          seq = OpenSSL::ASN1.decode(der)
          r = seq.value[0].value
          s = seq.value[1].value
          i2osp(r, n_bytes) + i2osp(s, n_bytes)
        end

        # Convert raw r‖s octets back to ASN.1 DER.
        def raw_to_der(raw, n_bytes)
          raise ArgumentError, "raw signature has wrong size" if raw.bytesize != (2 * n_bytes)

          r = raw.byteslice(0, n_bytes)
          s = raw.byteslice(n_bytes, n_bytes)
          seq = OpenSSL::ASN1::Sequence.new([
                                              OpenSSL::ASN1::Integer.new(asn1_integer_value(r)),
                                              OpenSSL::ASN1::Integer.new(asn1_integer_value(s)),
                                            ])
          seq.to_der
        end

        # Integer to octet stream (I2OSP), minimal length parameter.
        def i2osp(value, length)
          n = value.to_i
          raise ArgumentError, "I2OSP: integer too large" if n >= (1 << (8 * length))

          bytes = Array.new(length, 0)
          (length - 1).downto(0) do |i|
            bytes[i] = n & 0xff
            n >>= 8
          end
          bytes.pack("C*")
        end

        # Interpret an octet string as a positive integer (OS2IP).
        def asn1_integer_value(octets)
          octets.bytes.reduce(0) { |acc, byte| (acc << 8) | byte }
        end
      end
    end
  end
end
