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

    # Canonicalize using the named algorithm.
    #
    # +algorithm+ is one of:
    #   :inclusive_10  Canonical XML 1.0 (default; W3C REC-xml-c14n-20010315)
    #   :inclusive_11  Canonical XML 1.1 (W3C REC-xml-c14n11-20080502)
    #   :exclusive_10  Exclusive C14N 1.0 (W3C REC-xml-exc-c14n-20020718)
    #
    # Input accepts a Moxml::Node, Moxml::Document, or XML String.
    # Returns canonical UTF-8 octets.
    def self.canonicalize(node_or_xml, with_comments: false,
                          algorithm: :inclusive_10, inclusive_namespaces: [])
      engine_for(algorithm).canonicalize(
        node_or_xml,
        with_comments: with_comments,
        inclusive_namespaces: inclusive_namespaces,
      )
    end

    # Convenience: inclusive C14N 1.0 (the most common case).
    def self.canonicalize_inclusive_10(node_or_xml, with_comments: false)
      Inclusive10.new.canonicalize(node_or_xml, with_comments: with_comments)
    end

    # Convenience: inclusive C14N 1.1.
    def self.canonicalize_inclusive_11(node_or_xml, with_comments: false)
      Inclusive11.new.canonicalize(node_or_xml, with_comments: with_comments)
    end

    # Convenience: exclusive C14N 1.0. Renders only namespaces visibly
    # utilized by the apex element and its descendants. Used to keep
    # signatures portable across ancestor contexts.
    def self.canonicalize_exclusive(node_or_xml, with_comments: false,
                                    inclusive_namespaces: [])
      Exclusive.new.canonicalize(
        node_or_xml,
        with_comments: with_comments,
        inclusive_namespaces: inclusive_namespaces,
      )
    end

    # Compare two XML inputs by their canonical forms. Returns true iff
    # the canonical outputs are byte-identical.
    #
    # Useful for tests, diff reporting, and round-trip verification.
    def self.equivalent?(a, b, with_comments: false, algorithm: :inclusive_10,
                         inclusive_namespaces: [])
      canonicalize(a, with_comments: with_comments, algorithm: algorithm,
                   inclusive_namespaces: inclusive_namespaces) ==
        canonicalize(b, with_comments: with_comments, algorithm: algorithm,
                     inclusive_namespaces: inclusive_namespaces)
    end

    # Escape helpers used by both canon-ported code and Exclusive.
    # Prefer CharacterEncoder class methods in new code.
    def self.escape_text(text)
      CharacterEncoder.new.encode_text(text)
    end

    def self.escape_attribute(value)
      CharacterEncoder.new.encode_attribute(value)
    end

    # Internal: pick the engine class for a given algorithm symbol.
    def self.engine_for(algorithm)
      case algorithm
      when :inclusive_10 then Inclusive10.new
      when :inclusive_11 then Inclusive11.new
      when :exclusive_10 then Exclusive.new
      else
        raise ArgumentError,
              "unknown C14N algorithm #{algorithm.inspect}; expected one of " \
              ":inclusive_10, :inclusive_11, :exclusive_10"
      end
    end
    private_class_method :engine_for
  end
end
