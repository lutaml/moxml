# frozen_string_literal: true

module Moxml
  module XPath
    # Module for converting XPath objects such as NodeSets to different types.
    #
    # @private
    module Conversion
      # Converts both arguments to a type that can be compared using ==.
      #
      # @param [Object] left
      # @param [Object] right
      # @return [Array<Object, Object>]
      def self.to_compatible_types(left, right)
        if left.is_a?(Moxml::NodeSet) || left.respond_to?(:text)
          left = to_string(left)
        end

        if right.is_a?(Moxml::NodeSet) || right.respond_to?(:text)
          right = to_string(right)
        end

        if left.is_a?(Numeric) && !right.is_a?(Numeric)
          right = to_float(right)
        end

        if left.is_a?(String) && !right.is_a?(String)
          right = to_string(right)
        end

        if boolean?(left) && !boolean?(right)
          right = to_boolean(right)
        end

        [left, right]
      end

      # Converts a value to an XPath string.
      #
      # @param [Object] value
      # @return [String]
      def self.to_string(value)
        # If we have a number that has a zero decimal (e.g. 10.0) we want to
        # get rid of that decimal. For this we'll first convert the number to
        # an integer.
        if value.is_a?(Float) && value.modulo(1).zero?
          value = value.to_i
        end

        if value.is_a?(Moxml::NodeSet)
          value = first_node_text(value)
        end

        if value.respond_to?(:text)
          value = value.text
        end

        value.to_s
      end

      # Converts a value to an XPath number (float).
      #
      # @param [Object] value
      # @return [Float]
      def self.to_float(value)
        if value.is_a?(Moxml::NodeSet)
          value = first_node_text(value)
        end

        if value.respond_to?(:text)
          value = value.text
        end

        if value == true
          1.0
        elsif value == false
          0.0
        else
          begin
            Float(value)
          rescue ArgumentError, TypeError
            Float::NAN
          end
        end
      end

      # Converts a value to an XPath boolean.
      #
      # @param [Object] value
      # @return [Boolean]
      def self.to_boolean(value)
        bool = false

        if value.is_a?(Float)
          bool = !value.nan? && !value.zero?
        elsif value.is_a?(Integer)
          bool = !value.zero?
        elsif value.respond_to?(:empty?)
          bool = !value.empty?
        elsif value
          bool = true
        end

        bool
      end

      # Checks if a value is a boolean.
      #
      # @param [Object] value
      # @return [Boolean]
      def self.boolean?(value)
        [true, false].include?(value)
      end

      # Gets the text of the first node in a NodeSet.
      #
      # @param [Moxml::NodeSet] set
      # @return [String]
      def self.first_node_text(set)
        set[0].respond_to?(:text) ? set[0].text : ""
      end
    end
  end
end
