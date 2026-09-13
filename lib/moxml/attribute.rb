# frozen_string_literal: true

module Moxml
  class Attribute < Node
    # Immutable between name= writes (which clear it via
    # clear_native_memo!), unlike element names that can change via
    # native adoption; the memo removes an adapter read per access.
    def name
      @name ||= adapter.attribute_name(@native)
    end

    def name=(new_name)
      # Mutation return contract (Adapter::Base): returns the native
      # to keep tracking — same object for in-place adapters, fresh
      # object for value-object adapters (leptris).
      context.bump_namespace_scope_generation
      @name = nil
      @native = adapter.set_attribute_name(@native, new_name)
    end

    # Returns the primary identifier for this attribute (its name)
    # @return [String] the attribute name
    def identifier
      name
    end

    def value
      val = @native.value.to_s
      # Same guard as Element#text: entity-free documents skip the
      # marker restore scans. The memo rides the owning element's
      # (attr natives have no entity probe); a detached attribute
      # wrapper falls back to the unconditional restore.
      parent = @parent_node
      if parent.nil? || parent.entity_bearing?
        adapter.restore_entities(val)
      else
        val
      end
    end

    alias content value

    # Returns raw native value without entity marker restoration.
    def raw_value
      @native.value
    end

    def value=(new_value)
      name = self.name
      if name == "xmlns" || name.start_with?("xmlns:")
        # Declaration rewrite — namespace scope changed
        context.bump_namespace_scope_generation
      else
        @parent_node&.invalidate_attribute_value_cache!
      end
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
      # The name must be read before the removal — engines free the
      # attribute native, and post-removal reads are use-after-free.
      name = self.name
      declaration = name == "xmlns" || name.start_with?("xmlns:")
      adapter.remove_attribute_native(@native)
      if @parent_node.is_a?(Moxml::Element)
        if declaration
          @parent_node.invalidate_attribute_cache!
        else
          @parent_node.invalidate_local_attribute_cache!
        end
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
