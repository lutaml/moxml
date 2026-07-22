# frozen_string_literal: true

require "openssl"

module Moxml
  module Signature
    module Algorithms
      # DSA signature methods per FIPS 186-3.
      #
      # Two URIs:
      #   - SHA1 (1024-bit, q=160): wire format r‖s with 20-byte halves
      #   - SHA256 (2048-bit, q=256): wire format r‖s with N-byte halves
      #     where N = byte length of q (32 for SHA-256 case)
      #
      # OpenSSL returns DER; we convert to raw r‖s.
      class DsaSha < SignatureMethodBase
        PAIRINGS = {
          "http://www.w3.org/2000/09/xmldsig#dsa-sha1" => "SHA1",
          "http://www.w3.org/2009/xmldsig11#dsa-sha256" => "SHA256",
        }.freeze

        PAIRINGS.each_key { |uri| identifier uri }

        def initialize(identifier_uri:, parameters: nil)
          super(nil)
          @identifier_uri = identifier_uri
          @parameters = parameters
        end

        def compute_signature(data, key)
          dsa = coerce_signing_key(key)
          digest_name = self.class::PAIRINGS.fetch(@identifier_uri)
          der_signature = dsa.sign(digest_name, data)
          der_to_raw(der_signature, coordinate_bytes_for(dsa))
        end

        def verify_signature(data, key, signature)
          dsa = coerce_verify_key(key)
          digest_name = self.class::PAIRINGS.fetch(@identifier_uri)
          n_bytes = coordinate_bytes_for(dsa)
          der_signature = raw_to_der(signature, n_bytes)
          dsa.verify(digest_name, der_signature, data)
        rescue ArgumentError
          false
        end

        private

        def coerce_signing_key(key)
          case key
          when OpenSSL::PKey::DSA
            key
          else
            raise SignatureKeyError,
                  "DSA signature method requires OpenSSL::PKey::DSA, " \
                  "got #{key.class}"
          end
        end

        def coerce_verify_key(key)
          coerce_signing_key(key)
        end

        def coordinate_bytes_for(dsa)
          # q is the subgroup order. byte length of q.
          q_bits = dsa.q.num_bits
          (q_bits + 7) / 8
        end

        def der_to_raw(der, n_bytes)
          seq = OpenSSL::ASN1.decode(der)
          r = seq.value[0].value
          s = seq.value[1].value
          i2osp(r, n_bytes) + i2osp(s, n_bytes)
        end

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

        def asn1_integer_value(octets)
          octets.bytes.reduce(0) { |acc, byte| (acc << 8) | byte }
        end
      end
    end
  end
end
