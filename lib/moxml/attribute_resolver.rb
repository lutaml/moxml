# frozen_string_literal: true

module Moxml
  # Canonical, adapter-independent attribute-name resolution.
  #
  # XML Namespaces 1.0 semantics, implemented once on the Moxml object
  # model (the unified interface); adapters provide raw access only:
  #
  # - An attribute's expanded name is (namespace URI or none) + local
  #   name. Unprefixed attributes are never in a namespace — the
  #   default namespace declaration does not apply to attributes
  #   (Namespaces 1.0 §5.2).
  # - "prefix:local" resolves the prefix against the element's
  #   in-scope declarations and matches by expanded name: an attribute
  #   written as q:type matches a lookup as p:type whenever both
  #   prefixes are bound to the same URI.
  # - "xml" is prebound to the XML namespace URI; it never needs a
  #   declaration (Namespaces 1.0 §4).
  # - "xmlns"/"xmlns:*" are declarations, not attributes: never match.
  # - An undeclared prefix names nothing: nil. No silent prefix-string
  #   or bare-name fallback.
  #
  # When several attributes match (only possible in namespace-ill-formed
  # documents), the first in document order wins, matching every
  # adapter's attributes() ordering contract.
  module AttributeResolver
    XML_NAMESPACE_URI = "http://www.w3.org/XML/1998/namespace"

    module_function

    # @return [Moxml::Attribute, nil] the matching attribute wrapper
    def resolve(element, name)
      name = name.to_s
      if name.include?(":")
        prefix, local = name.split(":", 2)
        return nil if prefix == "xmlns"

        uri = prefix_uri(element, prefix)
        return nil if uri.nil?

        element.attributes.find do |attr|
          local_name(attr.name) == local && attribute_uri(element, attr) == uri
        end
      else
        element.attributes.find do |attr|
          local_name(attr.name) == name && attribute_uri(element, attr).nil?
        end
      end
    end

    # URI a prefix is bound to for lookups on this element, or nil when
    # the prefix is undeclared.
    def prefix_uri(element, prefix)
      return XML_NAMESPACE_URI if prefix == "xml"

      element.in_scope_namespaces
        .find { |candidate| candidate.prefix == prefix }&.uri
    end

    # Local part of a wrapper attribute name. Local names cannot
    # contain ':' in namespace-well-formed documents; splitting is for
    # adapters whose natives carry the qualified name (leptris).
    def local_name(name)
      name.include?(":") ? name.split(":", 2)[1] : name
    end

    # URI of an attribute's namespace, nil for the no-namespace case.
    #
    # Uses the attribute's own namespace when the native binding
    # exposes one with a URI (nokogiri/oga/libxml, and rexml/ox for
    # declared prefixes). Otherwise reconstructs it from the attribute
    # prefix via the element's in-scope declarations — covering
    # adapters that report a prefix without resolving it (rexml/ox for
    # the prebound xml prefix) and adapters that expose neither
    # namespace nor separate prefix (leptris qualified names).
    def attribute_uri(element, attr)
      ns = attr.namespace
      return ns.uri unless ns.nil? || ns.uri.to_s.empty?

      prefix = ns&.prefix || prefix_part(attr.name)
      return nil if prefix.nil? || prefix.empty?
      return XML_NAMESPACE_URI if prefix == "xml"

      element.in_scope_namespaces
        .find { |candidate| candidate.prefix == prefix }&.uri
    end

    def prefix_part(name)
      name.include?(":") ? name.split(":", 2)[0] : nil
    end
  end
end
