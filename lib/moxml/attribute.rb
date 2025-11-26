# frozen_string_literal: true

module Moxml
  class Attribute < Node
    def name
      @native.name
    end

    def name=(new_name)
      adapter.set_attribute_name(@native, new_name)
    end

    # Returns the primary identifier for this attribute (its name)
    # @return [String] the attribute name
    def identifier
      name
    end

    def value
      @native.value
    end

    def value=(new_value)
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
      adapter.set_namespace(@native, ns&.native)
    end

    def element
      adapter.attribute_element(@native)
    end

    def remove
      adapter.remove_attribute(element, name)
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
