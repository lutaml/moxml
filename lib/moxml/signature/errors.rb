# frozen_string_literal: true

module Moxml
  module Signature
    class Error < ::Moxml::Error; end

    class SignatureError < Error; end

    class UnknownAlgorithm < Error
      attr_reader :category, :uri

      def initialize(category, uri)
        @category = category
        @uri = uri
        super("Unknown #{category} algorithm: #{uri}")
      end
    end

    class DuplicateAlgorithm < Error
      attr_reader :category, :uri

      def initialize(category, uri)
        @category = category
        @uri = uri
        super("Algorithm already registered for #{category}: #{uri}")
      end
    end

    class SigningError < Error
      attr_reader :algorithm

      def initialize(message, algorithm: nil)
        @algorithm = algorithm
        super(message)
      end
    end

    class VerificationError < Error
      attr_reader :signature_id

      def initialize(message, signature_id: nil)
        @signature_id = signature_id
        super(message)
      end
    end

    class ReferenceDigestMismatch < VerificationError
      attr_reader :reference_uri, :expected, :computed

      def initialize(reference_uri:, expected:, computed:, signature_id: nil)
        @reference_uri = reference_uri
        @expected = expected
        @computed = computed
        super(
          "Digest mismatch for reference #{reference_uri.inspect}",
          signature_id: signature_id,
        )
      end
    end

    class SignatureValueMismatch < VerificationError
      attr_reader :algorithm

      def initialize(algorithm: nil, signature_id: nil)
        @algorithm = algorithm
        super("SignatureValue did not verify", signature_id: signature_id)
      end
    end

    class TransformError < Error
      attr_reader :algorithm

      def initialize(message, algorithm: nil)
        @algorithm = algorithm
        super(message)
      end
    end

    class CanonicalizationError < Error
      attr_reader :algorithm

      def initialize(message, algorithm: nil)
        @algorithm = algorithm
        super(message)
      end
    end

    class MalformedSignatureError < Error
      attr_reader :detail

      def initialize(message, detail: nil)
        @detail = detail
        super(message)
      end
    end

    class SignatureKeyError < Error; end
  end
end
