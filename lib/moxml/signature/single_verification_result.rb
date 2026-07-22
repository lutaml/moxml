# frozen_string_literal: true

module Moxml
  module Signature
    # Verification outcome for a single Signature element. Carries the
    # cryptographic-result boolean, per-reference results, and (when
    # applicable) the error that caused failure.
    class SingleVerificationResult
      attr_reader :signature_id, :references, :error

      def initialize(signature_id:, signature_valid:, references:, error: nil)
        @signature_id = signature_id
        @signature_valid = signature_valid
        @references = references
        @error = error
      end

      def signature_valid?
        @signature_valid
      end

      def valid?
        @signature_valid && references.all?(&:valid?)
      end

      def failing_references
        references.reject(&:valid?)
      end
    end
  end
end
