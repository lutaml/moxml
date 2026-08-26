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
          # attr.name allocates on several adapters (native string,
          # plus leptris' force_encoding dup) — read it once per probe
          attr_name = attr.name
          local_name(attr_name) == local && attribute_uri(element, attr, attr_name) == uri
        end
      else
        element.attributes.find do |attr|
          attr_name = attr.name
          local_name(attr_name) == name && attribute_uri(element, attr, attr_name).nil?
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

    # Assign a value to the attribute named by XML-correct resolution,
    # mirroring #resolve:
    #
    # - "xmlns"/"xmlns:*" are namespace declarations, not attributes:
    #   delegated verbatim to the adapter (declaration creation is
    #   adapter territory).
    # - A bare name replaces the no-namespace attribute only — a
    #   namespaced attribute sharing the local name is left alone.
    # - A prefixed name replaces by expanded name: assigning p:x
    #   overwrites an attribute spelled q:x when both prefixes are
    #   bound to the same URI.
    #
    # When nothing matches, the attribute is created with the given
    # spelling. A prefix not yet in scope is stored raw — builders
    # legitimately write detached children before attaching them under
    # the declaring ancestor, and reads resolve by expanded name once
    # the prefix is in scope (matching nokogiri/libxml creation
    # behavior; namespace validity is a property of the serialized
    # document).
    #
    # @return [String] the assigned value
    def assign(element, name, value)
      name = name.to_s
      adapter = element.context.config.adapter
      if name == "xmlns" || name.start_with?("xmlns:")
        adapter.set_attribute(element.native, name, value)
        element.invalidate_attribute_cache!
        return value
      end

      existing = resolve(element, name)
      if existing
        existing.value = value
        return value
      end

      adapter.set_attribute(element.native, name, value)
      element.invalidate_attribute_cache!
      value
    end

    # Remove the attribute named by XML-correct resolution (see
    # #assign for the name semantics).
    #
    # @return [Moxml::Attribute, nil] the removed attribute
    def remove(element, name)
      name = name.to_s
      adapter = element.context.config.adapter
      if name == "xmlns" || name.start_with?("xmlns:")
        adapter.remove_attribute(element.native, name)
        element.invalidate_attribute_cache!
        return nil
      end

      attr = resolve(element, name)
      return nil unless attr

      adapter.remove_attribute_native(attr.native)
      element.invalidate_attribute_cache!
      attr
    end

    # XPath 1.0 attribute node test, sharing the resolver's
    # expanded-name semantics:
    #
    # @param prefix [String, Symbol, nil]
    #   - String: match by namespace URI resolved against the
    #     element's in-scope declarations; the prefix spelling is
    #     irrelevant (q:x matches a p:x test when URIs agree)
    #   - :any: any namespace, including none (*:local)
    #   - nil: bare name — no-namespace attributes only (Namespaces
    #     1.0 §5.2)
    # @param local [String, nil] local name, or nil for any (p:*)
    # @return [Boolean]
    def attribute_test?(element, attr, prefix, local)
      return false if local && local_name(attr.name) != local

      case prefix
      when :any then true
      when nil then attribute_uri(element, attr).nil?
      else
        uri = prefix_uri(element, prefix)
        !uri.nil? && uri == attribute_uri(element, attr)
      end
    end

    # Attribute node test with a URI resolved at XPath compile time
    # (the static context's prefix mapping wins over the document's
    # own declarations). See #attribute_test? for local semantics.
    #
    # @return [Boolean]
    def attribute_test_uri?(element, attr, uri, local)
      return false if local && local_name(attr.name) != local

      attribute_uri(element, attr) == uri
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
    def attribute_uri(element, attr, attr_name = nil)
      ns = attr.namespace
      return ns.uri unless ns.nil? || ns.uri.to_s.empty?

      prefix = ns&.prefix || prefix_part(attr_name || attr.name)
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
