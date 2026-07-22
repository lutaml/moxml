# frozen_string_literal: true

require "openssl"

module Moxml
  module Signature
    module Algorithms
      # HMAC per RFC 2104, bound to a digest.
      #
      # Per W3C XML Signature §4.4.2 and §6.3.1, if `HMACOutputLength` is
      # specified, the output is truncated to that many bits and the
      # truncation length MUST be at least max(hash_bits / 2, 80) bits.
      class HmacSha < SignatureMethodBase
        PAIRINGS = {
          "http://www.w3.org/2000/09/xmldsig#hmac-sha1" => "SHA1",
          "http://www.w3.org/2001/04/xmldsig-more#hmac-sha224" => "SHA224",
          "http://www.w3.org/2001/04/xmldsig-more#hmac-sha256" => "SHA256",
          "http://www.w3.org/2001/04/xmldsig-more#hmac-sha384" => "SHA384",
          "http://www.w3.org/2001/04/xmldsig-more#hmac-sha512" => "SHA512",
        }.freeze

        HASH_BITS = {
          "SHA1" => 160,
          "SHA224" => 224,
          "SHA256" => 256,
          "SHA384" => 384,
          "SHA512" => 512,
        }.freeze

        MIN_TRUNCATION_BITS = 80

        PAIRINGS.each_key { |uri| identifier uri }

        # parameters: optional { hmac_output_length: Integer } (bits, multiple of 8)
        def initialize(identifier_uri:, parameters: nil)
          super(parameters)
          @identifier_uri = identifier_uri
          @truncation_bits = parameters&.dig(:hmac_output_length)
          validate_truncation! if @truncation_bits
        end

        def compute_signature(data, key)
          secret = coerce_key(key)
          full = OpenSSL::HMAC.digest(digest_name, secret, data)
          truncate(full)
        end

        def verify_signature(data, key, signature)
          expected = compute_signature(data, key)
          fixed_comparison(expected, signature)
        end

        private

        def digest_name
          PAIRINGS.fetch(@identifier_uri)
        end

        def hash_bits
          HASH_BITS.fetch(digest_name)
        end

        def truncate(full_mac)
          return full_mac unless @truncation_bits

          unless (@truncation_bits % 8).zero?
            raise SignatureError,
                  "HMACOutputLength (#{@truncation_bits}) must be a " \
                  "multiple of 8"
          end

          min = [hash_bits / 2, MIN_TRUNCATION_BITS].max
          if @truncation_bits < min
            raise SignatureError,
                  "HMACOutputLength (#{@truncation_bits}) below minimum " \
                  "of #{min} for #{digest_name}"
          end

          full_mac.byteslice(0, @truncation_bits / 8)
        end

        def validate_truncation!
          unless (@truncation_bits % 8).zero?
            raise SignatureError,
                  "HMACOutputLength (#{@truncation_bits}) must be a " \
                  "multiple of 8"
          end

          min = [hash_bits / 2, MIN_TRUNCATION_BITS].max
          return if @truncation_bits >= min

          raise SignatureError,
                "HMACOutputLength (#{@truncation_bits}) below minimum " \
                "of #{min} for #{digest_name}"
        end

        def coerce_key(key)
          case key
          when String then key
          else
            raise SignatureKeyError,
                  "HMAC signature method requires a String secret, " \
                  "got #{key.class}"
          end
        end

        def fixed_comparison(expected, actual)
          return false unless expected.bytesize == actual.bytesize

          OpenSSL.fixed_length_secure_compare(expected, actual)
        rescue ArgumentError
          false
        end
      end
    end
  end
end
