# frozen_string_literal: true

module Moxml
  # Canonicalization engine.
  #
  # Core XML operation — every XML library has C14N. Lives at the moxml
  # top level so it can be used by both the signature module and any
  # future moxml-aware tooling (the sibling `canon` gem, for instance,
  # has its own C14N implementation that could eventually migrate here
  # to avoid duplication).
  #
  # Sub-modules implement specific W3C canonicalization algorithms
  # against the Moxml::Node tree. Output is always UTF-8 octets
  # (no BOM, NFC characters preserved).
  module C14n
    autoload :Writer, "moxml/c14n/writer"
    autoload :NamespaceContext, "moxml/c14n/namespace_context"
    autoload :Exclusive, "moxml/c14n/exclusive"
    autoload :Inclusive10, "moxml/c14n/inclusive_10"
    autoload :Inclusive11, "moxml/c14n/inclusive_11"

    XMLNS_URI = "http://www.w3.org/2000/xmlns/"
    XML_URI = "http://www.w3.org/XML/1998/namespace"

    # Escape a text node's character content per C14N rules.
    def self.escape_text(text)
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
