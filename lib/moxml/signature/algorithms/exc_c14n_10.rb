# frozen_string_literal: true

module Moxml
  module Signature
    module Algorithms
      # Exclusive XML Canonicalization 1.0 (https://www.w3.org/TR/xml-exc-c14n/)
      #
      # Two registered URIs: one omits comments, one includes comments.
      class ExcC14n10 < CanonicalizationBase
        identifier "http://www.w3.org/2001/10/xml-exc-c14n#",
                   with_comments: false
        identifier "http://www.w3.org/2001/10/xml-exc-c14n#WithComments",
                   with_comments: true

        def initialize(identifier_uri: nil, with_comments: nil,
                       inclusive_namespaces: [])
          super
          # If the URI is the WithComments variant, default with_comments true.
          return if !identifier_uri.nil?
          return if !with_comments.nil?

          @with_comments = false
        end

        private

        def engine
          C14n::Exclusive.new
        end
      end
    end
  end
end
