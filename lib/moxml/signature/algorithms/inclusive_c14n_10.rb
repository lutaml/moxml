# frozen_string_literal: true

module Moxml
  module Signature
    module Algorithms
      # Canonical XML 1.0 (https://www.w3.org/TR/xml-c14n/)
      #
      # Implemented via the canon-derived C14n::Inclusive10 engine.
      class InclusiveC14n10 < CanonicalizationBase
        identifier "http://www.w3.org/TR/2001/REC-xml-c14n-20010315"
        identifier "http://www.w3.org/TR/2001/REC-xml-c14n-20010315#WithComments"

        private

        def engine
          C14n::Inclusive10.new
        end
      end
    end
  end
end
