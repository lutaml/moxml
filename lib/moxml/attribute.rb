# frozen_string_literal: true

module Moxml
  class Attribute < Node
    def name
      adapter.attribute_name(@native)
    end

    def name=(new_name)
      # Mutation return contract (Adapter::Base): returns the native
      # to keep tracking — same object for in-place adapters, fresh
      # object for value-object adapters (leptris).
      context.bump_namespace_scope_generation
      @native = adapter.set_attribute_name(@native, new_name)
    end

    # Returns the primary identifier for this attribute (its name)
    # @return [String] the attribute name
    def identifier
      name
    end

    def value
      val = @native.value.to_s
      adapter.restore_entities(val)
    end

    alias content value

    # Returns raw native value without entity marker restoration.
    def raw_value
      @native.value
    end

    def value=(new_value)
      context.bump_namespace_scope_generation
      adapter.set_attribute_value(@native, new_value)
    end

    # XPath conversion compatibility - attributes need .text method
    # that returns their value for XPath comparisons
    def text
      value
    end

    def namespace
      ns = adapter.namespace(@native)
      ns && Namespace.new(ns, context)
    end

    def namespace=(ns)
      # See name= for the mutation return contract.
      @native = adapter.set_namespace(@native, ns&.native)
    end

    def element
      native_elem = adapter.attribute_element(@native)
      native_elem && Moxml::Node.wrap(native_elem, context)
    end

    def remove
      adapter.remove_attribute_native(@native)
      if @parent_node.is_a?(Moxml::Element)
        @parent_node.invalidate_attribute_cache!
      end
      self
    end

    def ==(other)
      return false unless other.is_a?(Attribute)

      name == other.name && value == other.value && namespace == other.namespace
    end

    def to_s
      if namespace&.prefix
        "#{namespace.prefix}:#{name}=\"#{value}\""
      else
        "#{name}=\"#{value}\""
      end
    end

    def attribute?
      true
    end

    protected

    def adapter
      context.config.adapter
    end
  end
end
