# frozen_string_literal: true

require_relative "attribute"
require_relative "namespace"

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

    def []=(name, value)
      adapter.set_attribute(@native, name, normalize_xml_value(value))
      @attributes = nil
    end

    def [](name)
      val = adapter.get_attribute_value(@native, name)
      val ? adapter.restore_entities(val) : val
    end

    def attribute(name)
      native_attr = adapter.get_attribute(@native, name)
      native_attr && Attribute.new(native_attr, context)
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
      adapter.remove_attribute(@native, name)
      @attributes = nil
      self
    end

    def add_namespace(prefix, uri)
      adapter.create_namespace(@native, prefix, uri,
                               namespace_validation_mode: context.config.namespace_validation_mode)
      @namespaces = nil
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
      @namespaces = nil
    end

    def namespaces
      @namespaces ||= adapter.namespace_definitions(@native).map do |ns|
        Namespace.new(ns, context)
      end
    end
    alias namespace_definitions namespaces

    # Returns all namespaces in scope for this element,
    # including those inherited from ancestor elements.
    def in_scope_namespaces
      adapter.in_scope_namespaces(@native).map do |ns|
        Namespace.new(ns, context)
      end
    end

    # Returns the namespace URI of this element (alias for namespace_uri)
    def namespace_name
      namespace_uri
    end

    def text
      val = adapter.text_content(@native)
      adapter.restore_entities(val)
    end

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
      doc = context.parse("<root>#{xml}</root>")
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
  end
end
