# frozen_string_literal: true

module Moxml
  module SAX
    # Splits a flat attribute hash into regular attributes and namespace declarations.
    #
    # Every adapter SAX bridge performs the same split: attributes whose names
    # start with "xmlns" are namespace declarations, everything else is a regular
    # attribute. This module provides a single implementation.
    module NamespaceSplitter
      # @param attributes [Hash, Array<Array>] attributes as a hash or array of pairs
      # @return [Array(Hash, Hash)] [regular_attrs, namespaces]
      def split_attributes_and_namespaces(attributes)
        attrs = {}
        ns = {}

        each_attribute(attributes) do |name, value|
          name_s = name.to_s
          if name_s == "xmlns" || name_s.start_with?("xmlns:")
            prefix = name_s == "xmlns" ? nil : name_s.sub("xmlns:", "")
            ns[prefix] = value
          else
            attrs[name_s] = value
          end
        end

        [attrs, ns]
      end

      private

      def each_attribute(attributes, &block)
        case attributes
        when Hash
          attributes.each(&block)
        when Array
          attributes.each { |pair| yield pair[0], pair[1] }
        when nil
          # nothing
        else
          if attributes.respond_to?(:each)
            attributes.each do |item|
              if item.is_a?(Array) && item.size >= 2
                yield item[0], item[1]
              elsif item.respond_to?(:name) && item.respond_to?(:value)
                yield item.name, item.value
              end
            end
          end
        end
      end
    end
  end
end
