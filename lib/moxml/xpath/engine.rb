# frozen_string_literal: true

module Moxml
  module XPath
    # XPath 1.0 evaluation engine
    #
    # This engine provides complete XPath 1.0 support for Moxml documents,
    # particularly useful for the Ox adapter which has limited native XPath.
    #
    # @example Evaluate XPath expression
    #   engine = Moxml::XPath::Engine.new(document)
    #   results = engine.evaluate("//book[@id='123']/title")
    #
    # @example With context node
    #   engine = Moxml::XPath::Engine.new(document)
    #   results = engine.evaluate("./author", context: book_element)
    #
    class Engine
      attr_reader :document

      # Initialize engine with a document
      #
      # @param document [Moxml::Document] The document to query
      def initialize(document)
        @document = document
      end

      # Evaluate an XPath expression
      #
      # @param expression [String] XPath expression to evaluate
      # @param context [Moxml::Node, nil] Context node (defaults to document root)
      # @return [Moxml::NodeSet, String, Numeric, Boolean] Result depends on expression
      # @raise [Moxml::XPath::SyntaxError] If expression syntax is invalid
      # @raise [Moxml::XPath::EvaluationError] If evaluation fails
      def evaluate(expression, context: nil)
        raise ::NotImplementedError, "XPath engine implementation in progress (Phase 1.1+)"
      end

      # Check if expression is valid XPath syntax
      #
      # @param expression [String] XPath expression to validate
      # @return [Boolean] true if valid, false otherwise
      def valid?(expression)
        evaluate(expression, context: document.root)
        true
      rescue Moxml::XPath::SyntaxError
        false
      end
    end
  end
end