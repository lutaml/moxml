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
      # @yieldparam value [Object] raw attribute/namespace value
      # @yieldreturn [Object] transformed value to store
      # @return [Array(Hash, Hash)] [regular_attrs, namespaces]
      # Shared for the overwhelmingly common no-declaration element:
      # one Hash allocation per start_element event saved. Frozen —
      # event hashes are read-only data, not scratch.
      EMPTY_NAMESPACES = {}.freeze

      def split_attributes_and_namespaces(attributes)
        attrs = {}
        ns = nil

        each_attribute(attributes) do |name, value|
          name_s = name.to_s
          if name_s.start_with?("xmlns")
            if name_s == "xmlns"
              (ns ||= {})[nil] = block_given? ? yield(value) : value
            elsif name_s.bytesize > 5 && name_s.getbyte(5) == 58 # ":"
              (ns ||= {})[name_s[6..]] = block_given? ? yield(value) : value
            else
              attrs[name_s] = block_given? ? yield(value) : value
            end
          else
            attrs[name_s] = block_given? ? yield(value) : value
          end
        end

        [attrs, ns || EMPTY_NAMESPACES]
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
          if attributes.is_a?(Enumerable)
            attributes.each do |item|
              case item
              when Array
                yield item[0], item[1] if item.size >= 2
              else
                yield item.name, item.value
              end
            end
          end
        end
      end
    end
  end
end
