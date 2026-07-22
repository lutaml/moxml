# frozen_string_literal: true

module Moxml
  module Signature
    module Algorithms
      # Canonical XML 1.1 (https://www.w3.org/TR/xml-c14n11/)
      #
      # Status: stub — currently delegates to Inclusive 1.0. Full 1.1
      # differences (XML 1.1 line-ending handling, additional notations)
      # are documented in TODO.complete/05-c14n-engine.md.
      class InclusiveC14n11 < CanonicalizationBase
        identifier "http://www.w3.org/2006/12/xml-c14n11",
                   with_comments: false
        identifier "http://www.w3.org/2006/12/xml-c14n11#WithComments",
                   with_comments: true

        private

        def engine
          C14n::Inclusive10.new
        end
      end
    end
  end
end
