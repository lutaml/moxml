# frozen_string_literal: true

module Moxml
  module Attribute
    include Node

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
      # Engines allocate a fresh String per read (Nokogiri attr.value);
      # hydration walks re-read the same wrappers, so the value is
      # memoized. A held wrapper recomputes when its owner element's
      # value generation moves (element-side writes bump it locally —
      # a context-wide bump would evict every wrapper per bulk-build
      # write). Parentless wrappers (xpath ResultAttrs) are immutable
      # captures and memo unconditionally.
      if @parent_node
        generation = @parent_node.attribute_value_generation
        @value = nil if @value_gen != generation
        @value_gen = generation
      end
      @value ||= begin
        val = @native.value.to_s
        parent = @parent_node
        if parent.nil? || parent.entity_bearing?
          adapter.restore_entities(val)
        else
          val
        end
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
      @value = nil
      adapter.set_attribute_value(@native, new_value)
    end

    # XPath conversion compatibility - attributes need .text method
    # that returns their value for XPath comparisons
    def text
      value
    end

    def namespace
      ns = adapter.namespace(@native)
      ns && Wrappers::Namespace.new(ns, context)
    end

    def namespace=(ns)
      # See name= for the mutation return contract.
      @native = adapter.set_namespace(@native, ns&.native)
    end

    def element
      native_elem = adapter.attribute_element(@native)
      native_elem && Moxml::Node.wrap(native_elem, context)
    end

    # The wrapper's parent tracking is authoritative for attributes
    # (set at materialization by Element#attributes): the generic
    # adapter read raises on engines whose Attr natives expose no
    # #parent (leptris), and the tracked value needs no wrap.
    def parent
      @parent_node
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
