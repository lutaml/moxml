# frozen_string_literal: true

module Moxml
  module Signature
    module Algorithms
      # Exclusive XML Canonicalization 1.0 (https://www.w3.org/TR/xml-exc-c14n/)
      #
      # Two registered URIs: one omits comments, one includes comments.
      # The with_comments variant is detected from the URI suffix at
      # instantiation time (see CanonicalizationBase#uri_has_comments?).
      class ExcC14n10 < CanonicalizationBase
        identifier "http://www.w3.org/2001/10/xml-exc-c14n#"
        identifier "http://www.w3.org/2001/10/xml-exc-c14n#WithComments"

        private

        def engine
          ::Moxml::C14n::Exclusive.new
        end
      end
    end
  end
end
