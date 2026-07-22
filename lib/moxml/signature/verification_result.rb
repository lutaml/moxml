# frozen_string_literal: true

module Moxml
  module Signature
    # Aggregated verification result for a document. A document may
    # contain multiple Signature elements; this result wraps them all.
    class VerificationResult
      attr_reader :results

      def initialize(results:)
        @results = results
      end

      def valid?
        results.all?(&:valid?)
      end

      def signature_count
        results.size
      end

      def failing
        results.reject(&:valid?)
      end
    end
  end
end
