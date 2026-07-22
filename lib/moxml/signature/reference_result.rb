# frozen_string_literal: true

module Moxml
  module Signature
    # Per-reference digest comparison result. `valid?` is true iff the
    # freshly-computed digest matches the expected DigestValue.
    class ReferenceResult
      attr_reader :uri, :digest_method, :expected, :computed

      def initialize(uri:, digest_method:, expected:, computed:)
        @uri = uri
        @digest_method = digest_method
        @expected = expected
        @computed = computed
      end

      def valid?
        expected == computed
      end
    end
  end
end
