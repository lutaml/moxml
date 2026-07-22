# frozen_string_literal: true

module Moxml
  module Signature
    module Algorithms
      # Base class for signature methods and MACs.
      #
      # Subclasses declare an identifier URI per W3C spec §6.4 / §6.3 and
      # implement #compute_signature and #verify_signature.
      #
      # `key` is whatever OpenSSL expects (OpenSSL::PKey::RSA for RSA, a
      # String secret for HMAC, etc.).
      class SignatureMethodBase
        class << self
          attr_reader :identifier_uri, :digest_uri

          def identifier(uri, digest_uri: nil)
            @identifier_uri = uri
            @digest_uri = digest_uri
            Algorithms.register(:signature_method, uri, self)
          end
        end

        # Optional constructor for parameterized methods (e.g. HMACOutputLength).
        def initialize(parameters = nil)
          @parameters = parameters
        end

        def sign(data, key)
          compute_signature(data, key)
        rescue OpenSSL::PKey::PKeyError => e
          raise SigningError.new(
            "signing failed: #{e.class}",
            algorithm: self.class.identifier_uri,
          )
        end

        def verify(data, key, signature)
          verify_signature(data, key, signature)
        rescue OpenSSL::PKey::PKeyError => e
          raise VerificationError.new(
            "verification raised: #{e.class}",
          )
        end

        def compute_signature(_data, _key)
          raise NotImplementedError,
                "#{self.class} must implement #compute_signature"
        end

        def verify_signature(_data, _key, _signature)
          raise NotImplementedError,
                "#{self.class} must implement #verify_signature"
        end
      end
    end
  end
end
