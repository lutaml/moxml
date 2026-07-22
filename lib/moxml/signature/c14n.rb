# frozen_string_literal: true

module Moxml
  module Signature
    # Canonicalization engine.
    #
    # Sub-modules implement specific W3C canonicalization algorithms against
    # the Moxml::Node tree. Output is always UTF-8 octets (no BOM, NFC
    # characters preserved).
    module C14n
      autoload :Writer, "moxml/signature/c14n/writer"
      autoload :NamespaceContext, "moxml/signature/c14n/namespace_context"
      autoload :Exclusive, "moxml/signature/c14n/exclusive"
      autoload :Inclusive10, "moxml/signature/c14n/inclusive_10"
      autoload :Inclusive11, "moxml/signature/c14n/inclusive_11"

      XMLNS_URI = "http://www.w3.org/2000/xmlns/"
      XML_URI = "http://www.w3.org/XML/1998/namespace"

      # Escape a text node's character content per C14N rules.
      def self.escape_text(text)
        # C14N: & < > are escaped; \r escaped as &#xD; (line ending normalization
        # already done by XML parser; \r is preserved only when literal in source).
        text.to_s
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
          .gsub("\r", "&#xD;")
      end

      # Escape an attribute value per C14N rules.
      def self.escape_attribute(value)
        value.to_s
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub("\"", "&quot;")
          .gsub("\t", "&#x9;")
          .gsub("\n", "&#xA;")
          .gsub("\r", "&#xD;")
      end
    end
  end
end
