# frozen_string_literal: true

require "openssl"

module Moxml
  module Signature
    module Algorithms
      # RSASSA-PKCS1-v1_5 per RFC 3447 §8.2, bound to a digest.
      #
      # One Ruby class registered under five URIs (sha1 / sha224 / sha256 /
      # sha384 / sha512). When instantiated, the class is told which URI was
      # resolved so it can pick the right digest.
      class RsaPkcs1Sha < SignatureMethodBase
        PAIRINGS = {
          "http://www.w3.org/2000/09/xmldsig#rsa-sha1" => "SHA1",
          "http://www.w3.org/2001/04/xmldsig-more#rsa-sha224" => "SHA224",
          "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256" => "SHA256",
          "http://www.w3.org/2001/04/xmldsig-more#rsa-sha384" => "SHA384",
          "http://www.w3.org/2001/04/xmldsig-more#rsa-sha512" => "SHA512",
        }.freeze

        PAIRINGS.each_key { |uri| identifier uri }

        def initialize(identifier_uri:, parameters: nil)
          super(nil)
          @identifier_uri = identifier_uri
          @parameters = parameters
        end

        def compute_signature(data, key)
          rsa_key = coerce_key(key)
          rsa_key.sign(digest_name, data)
        end

        def verify_signature(data, key, signature)
          rsa_key = coerce_key(key)
          rsa_key.verify(digest_name, signature, data)
        end

        private

        def digest_name
          PAIRINGS.fetch(@identifier_uri)
        end

        def coerce_key(key)
          return key if key.is_a?(OpenSSL::PKey::RSA)

          raise SignatureKeyError,
                "RSA signature method requires OpenSSL::PKey::RSA, " \
                "got #{key.class}"
        end
      end
    end
  end
end
