# frozen_string_literal: true

require_relative "handler"

module Moxml
  module SAX
    # Element-focused SAX handler with stack tracking
    #
    # Extends the base Handler with utilities for tracking element context:
    # - Element stack (current hierarchy)
    # - Current path (array of element names from root)
    # - Helper methods for checking context
    #
    # @example Using element context
    #   class MyHandler < Moxml::SAX::ElementHandler
    #     def on_start_element(name, attributes = {}, namespaces = {})
    #       super # Important: call super to update stack
    #
    #       if path_matches?(%r{/library/book/title$})
    #         puts "Found title at: #{current_path.join('/')}"
    #       end
    #     end
    #   end
    #
    class ElementHandler < Handler
      # @return [Array<String>] Stack of currently open elements
      attr_reader :element_stack

      # @return [Array<String>] Current path from root to current element
      attr_reader :current_path

      def initialize
        super
        @element_stack = []
        @current_path = []
      end

      # Tracks element on stack before calling super
      #
      # @param name [String] Element name
      # @param attributes [Hash] Element attributes
      # @param namespaces [Hash] Namespace declarations
      # @return [void]
      def on_start_element(name, attributes = {}, namespaces = {})
        @element_stack.push(name)
        @current_path.push(name)
        super
      end

      # Removes element from stack before calling super
      #
      # @param name [String] Element name
      # @return [void]
      def on_end_element(name)
        @element_stack.pop
        @current_path.pop
        super
      end

      # Check if currently inside an element with the given name
      #
      # @param name [String] Element name to check
      # @return [Boolean] true if inside the element
      # @example
      #   in_element?("book") # true if inside any <book> element
      def in_element?(name)
        @element_stack.include?(name)
      end

      # Get the name of the current (innermost) element
      #
      # @return [String, nil] Current element name, or nil if at document level
      # @example
      #   current_element # => "title"
      def current_element
        @element_stack.last
      end

      # Get the name of the parent element
      #
      # @return [String, nil] Parent element name, or nil if no parent
      # @example
      #   parent_element # => "book"
      def parent_element
        @element_stack[-2]
      end

      # Get current depth in the document tree
      #
      # @return [Integer] Current nesting level (0 at document root)
      # @example
      #   depth # => 3 (e.g., /library/book/title)
      def depth
        @element_stack.length
      end

      # Check if current path matches a pattern
      #
      # @param pattern [String, Regexp] Pattern to match against path
      # @return [Boolean] true if path matches
      # @example
      #   path_matches?(/book\/title$/) # true if at /*/book/title
      #   path_matches?("/library/book/title") # exact path match
      def path_matches?(pattern)
        path_str = "/#{@current_path.join('/')}"
        if pattern.is_a?(Regexp)
          !path_str.match?(pattern).nil?
        else
          path_str == pattern.to_s
        end
      end

      # Get the full path as a string
      #
      # @param separator [String] Path separator (default: "/")
      # @return [String] Full path string
      # @example
      #   path_string # => "/library/book/title"
      def path_string(separator = "/")
        separator + @current_path.join(separator)
      end
    end
  end
end