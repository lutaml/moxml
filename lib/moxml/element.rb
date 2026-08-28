# frozen_string_literal: true

module Moxml
  class Element < Node
    def name
      adapter.node_name(@native)
    end

    def name=(value)
      adapter.set_node_name(@native, value)
    end

    # Returns the primary identifier for this element (its tag name)
    # @return [String] the element name
    def identifier
      name
    end

    # Returns the expanded name including namespace prefix
    def expanded_name
      if namespace_prefix && !namespace_prefix.empty?
        "#{namespace_prefix}:#{name}"
      else
        name
      end
    end

    # Returns the namespace prefix of this element
    def namespace_prefix
      ns = namespace
      ns&.prefix
    end

    # Returns the namespace URI of this element
    def namespace_uri
      ns = namespace
      ns&.uri
    end

    # Write path shares the resolver's expanded-name semantics (see
    # AttributeResolver.assign): bare names target no-namespace
    # attributes only; prefixed names replace by namespace URI and
    # require a declared prefix. Cache coherence is the resolver's.
    def []=(name, value)
      Moxml::AttributeResolver.assign(self, name, normalize_xml_value(value))
    end

    # Unified XML-correct name resolution (see AttributeResolver):
    # bare names match only no-namespace attributes; prefixed names
    # resolve through in-scope declarations to expanded names.
    def [](name)
      Moxml::AttributeResolver.resolve(self, name)&.value
    end

    def attribute(name)
      Moxml::AttributeResolver.resolve(self, name)
    end

    # Returns attribute value by name (used by XPath engine)
    def get(attr_name)
      self[attr_name]
    end

    def attributes
      @attributes ||= adapter.attributes(@native).map do |attr|
        a = Attribute.new(attr, context)
        a.parent_node = self
        a
      end
    end

    def remove_attribute(name)
      Moxml::AttributeResolver.remove(self, name)
      self
    end

    def add_namespace(prefix, uri)
      adapter.create_namespace(@native, prefix, uri,
                               namespace_validation_mode: context.config.namespace_validation_mode)
      invalidate_namespace_cache!
      self
    rescue ValidationError => e
      # Re-raise as NamespaceError, provide attributes for error context
      # but the to_s will only add details if provided
      raise Moxml::NamespaceError.new(
        e.message,
        prefix: prefix,
        uri: uri,
        element: self,
      )
    end
    alias add_namespace_definition add_namespace

    # it's NOT the same as namespaces.first
    def namespace
      ns = adapter.namespace(@native)
      ns && Namespace.new(ns, context)
    end

    # add the prefix to the element name
    # and add the namespace to the list of namespace definitions
    def namespace=(ns_or_hash)
      if ns_or_hash.is_a?(Hash)
        adapter.set_namespace(
          @native,
          adapter.create_namespace(@native, *ns_or_hash.to_a.first,
                                   namespace_validation_mode: context.config.namespace_validation_mode),
        )
      else
        adapter.set_namespace(@native, ns_or_hash&.native)
      end
      invalidate_namespace_cache!
    end

    def namespaces
      @namespaces ||= adapter.namespace_definitions(@native).map do |ns|
        Namespace.new(ns, context)
      end
    end
    alias namespace_definitions namespaces

    # The element's OWN namespace declarations as [prefix, uri]
    # pairs (nil prefix = default namespace) — not the inherited
    # scope. The shape materialize records carry (issue #138).
    def declared_namespaces
      adapter.namespace_definitions(@native).map do |ns|
        wrapper = Namespace.new(ns, context)
        [wrapper.prefix, wrapper.uri]
      end
    end

    # Returns all namespaces in scope for this element,
    # including those inherited from ancestor elements.
    def in_scope_namespaces
      generation = context.namespace_scope_generation
      if @in_scope_namespaces.nil? || @in_scope_generation != generation
        @in_scope_namespaces = adapter.in_scope_namespaces(@native).map do |ns|
          Namespace.new(ns, context)
        end
        @in_scope_generation = generation
      end
      @in_scope_namespaces
    end

    # Returns the namespace URI of this element (alias for namespace_uri)
    def namespace_name
      namespace_uri
    end

    def text
      val = adapter.text_content(@native)
      adapter.restore_entities(val)
    end

    alias content text

    def text=(content)
      adapter.set_text_content(@native, normalize_xml_value(content))
      invalidate_children_cache!
    end

    def inner_text
      text = raw_inner_text
      adapter.restore_entities(text)
    end

    # Returns inner text without entity marker restoration.
    # Used internally when raw content with markers is needed (e.g., for DOM construction).
    def raw_inner_text
      adapter.inner_text(@native)
    end

    def inner_xml
      adapter.inner_xml(@native)
    end

    def inner_xml=(xml)
      wrapper = "_moxml_inner_#{Process.pid}_#{object_id}"
      doc = context.parse("<#{wrapper}>#{xml}</#{wrapper}>")
      adapter.replace_children(@native, doc.root.children.map(&:native))
      invalidate_children_cache!
    end

    # Fluent interface methods
    def with_attribute(name, value)
      self[name] = value
      self
    end

    def with_namespace(prefix, uri)
      add_namespace(prefix, uri)
      self
    end

    def with_text(content)
      self.text = content
      self
    end

    # Bulk attribute setting
    def set_attributes(attributes_hash)
      attributes_hash.each { |name, value| self[name] = value }
      self
    end

    # Chainable child addition
    def with_child(child)
      add_child(child)
      self
    end

    # Convenience find methods
    def find_element(xpath)
      at_xpath(xpath)
    end

    def find_all(xpath)
      xpath(xpath).to_a
    end

    # Alias for children (used by XPath engine)
    def nodes
      children
    end

    # Called by Attribute#remove to invalidate the cached attributes
    def invalidate_attribute_cache!
      @attributes = nil
    end

    # Clear the namespace caches and bump the context's scope
    # generation so every wrapper — including ones not reachable from
    # any children cache — recomputes on next read.
    def invalidate_namespace_cache!
      @namespaces = nil
      @in_scope_namespaces = nil
      context.bump_namespace_scope_generation
    end
  end
end
