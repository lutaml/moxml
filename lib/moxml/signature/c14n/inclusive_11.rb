# frozen_string_literal: true

module Moxml
  module Signature
    module C14n
      # Inclusive Canonical XML 1.1 (https://www.w3.org/TR/xml-c14n11/)
      #
      # Status: stub. Full implementation deferred to TODO.complete/05.
      class Inclusive11
        def canonicalize(node, with_comments: false, inclusive_namespaces: [])
          Exclusive.new.canonicalize(
            node,
            with_comments: with_comments,
            inclusive_namespaces: inclusive_namespaces,
          )
        end
      end
    end
  end
end
