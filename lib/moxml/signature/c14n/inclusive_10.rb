# frozen_string_literal: true

module Moxml
  module Signature
    module C14n
      # Inclusive Canonical XML 1.0 (https://www.w3.org/TR/xml-c14n/)
      #
      # Status: stub. Full implementation deferred to TODO.complete/05.
      # Falls back to Exclusive with the same prefix semantics as a
      # pragmatic approximation; this is NOT byte-compatible with
      # inclusive C14N for documents with inherited namespaces.
      class Inclusive10
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
