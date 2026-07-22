# frozen_string_literal: true

require "openssl"
require "base64"

module Moxml
  module Signature
    module Algorithms
      # Base class for message digest algorithms (SHA family).
      #
      # Subclasses MUST declare:
      #   - `identifier "http://..."` to register
      #   - either `digest_bits N` and `openssl_digest_name "SHA256"` etc.,
      #     OR override `#compute_digest`.
      class DigestBase
        class << self
          attr_reader :identifier_uri, :digest_size_bits

          def identifier(uri)
            @identifier_uri = uri
            Algorithms.register(:digest, uri, self)
          end

          def digest_bits(bits)
            @digest_size_bits = bits
          end

          def openssl_digest_name(name)
            define_method(:compute_digest) do |data|
              OpenSSL::Digest.digest(name, data)
            end
          end
        end

        def digest(data)
          compute_digest(data.to_s)
        end

        def digest_base64(data)
          Base64.strict_encode64(digest(data))
        end

        def compute_digest(_data)
          raise NotImplementedError,
                "#{self.class} must implement #compute_digest " \
                "or declare openssl_digest_name"
        end
      end
    end
  end
end
