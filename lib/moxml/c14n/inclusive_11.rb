# frozen_string_literal: true

module Moxml
  module C14n
    # Canonical XML 1.1 (https://www.w3.org/TR/xml-c14n11/).
    #
    # In this implementation, Inclusive11 is a thin alias of Inclusive10.
    # Both delegate to the canon-derived Processor. The W3C 1.1 additions
    # (notations, entity references in DTD internal subset, XML 1.1 line
    # ending) are rarely encountered in modern XML signature practice.
    class Inclusive11
      def canonicalize(node_or_xml, with_comments: false, inclusive_namespaces: [])
        Inclusive10.new.canonicalize(
          node_or_xml,
          with_comments: with_comments,
          inclusive_namespaces: inclusive_namespaces,
        )
      end
    end
  end
end
