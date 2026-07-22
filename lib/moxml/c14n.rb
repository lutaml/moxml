# frozen_string_literal: true

module Moxml
  # Canonicalization engine. Core moxml feature — sibling to
  # Moxml::XPath, Moxml::Builder, Moxml::SAX.
  #
  # Inclusive C14N (1.0 and 1.1) is ported from canon (lutaml/canon):
  # mature, tested, full-featured (xml:base fixup, inheritable xml:*
  # attribute resolution, node-set subset canonicalization).
  #
  # Exclusive C14N (1.0) is a moxml-native implementation; canon does
  # not implement exclusive. It is required by XML signature to keep
  # signatures valid when subdocuments are moved between contexts.
  module C14n
    autoload :Node, "moxml/c14n/node"
    autoload :Nodes, "moxml/c14n/nodes"
    autoload :DataModel, "moxml/c14n/data_model"
    autoload :Processor, "moxml/c14n/processor"
    autoload :CharacterEncoder, "moxml/c14n/character_encoder"
    autoload :NamespaceHandler, "moxml/c14n/namespace_handler"
    autoload :AttributeHandler, "moxml/c14n/attribute_handler"
    autoload :XmlBaseHandler, "moxml/c14n/xml_base_handler"

    # Engine classes used directly by signature algorithms.
    autoload :Writer, "moxml/c14n/writer"
    autoload :NamespaceContext, "moxml/c14n/namespace_context"
    autoload :Exclusive, "moxml/c14n/exclusive"
    autoload :Inclusive10, "moxml/c14n/inclusive_10"
    autoload :Inclusive11, "moxml/c14n/inclusive_11"

    XMLNS_URI = "http://www.w3.org/2000/xmlns/"
    XML_URI = "http://www.w3.org/XML/1998/namespace"

    # Default canonical form (inclusive C14N 1.0, no comments).
    def self.canonicalize(node_or_xml, with_comments: false)
      Inclusive10.new.canonicalize(node_or_xml, with_comments: with_comments)
    end

    # Exclusive C14N 1.0. Renders only namespaces visibly utilized by
    # the apex element and its descendants. Used to keep signatures
    # portable across ancestor contexts.
    def self.canonicalize_exclusive(node_or_xml, with_comments: false,
                                    inclusive_namespaces: [])
      Exclusive.new.canonicalize(
        node_or_xml,
        with_comments: with_comments,
        inclusive_namespaces: inclusive_namespaces,
      )
    end

    # Convenience: build a data model from a Moxml::Node or XML String,
    # then run the canonicalizer. Subset canonicalization (XPath node-set
    # membership) is the foundation of enveloped-signature handling.
    def self.canonicalize_subset(node_or_xml, matched_nodes, with_comments: false)
      root = node_or_xml.is_a?(Nodes::RootNode) ? node_or_xml : DataModel.from_node_or_xml(node_or_xml)
      DataModel.mark_all(root, false)
      DataModel.mark_subset(root, matched_nodes)
      Processor.new(with_comments: with_comments).process(root)
    end

    # Escape helpers used by both canon-ported code and Exclusive.
    def self.escape_text(text)
      text.to_s
        .gsub("&", "&amp;")
        .gsub("<", "&lt;")
        .gsub(">", "&gt;")
        .gsub("\r", "&#xD;")
    end

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
