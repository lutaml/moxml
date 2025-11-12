# frozen_string_literal: true

module Moxml
  module XPath
    # Base error for XPath-specific errors
    # Inherits from Moxml::XPathError to maintain compatibility
    class Error < Moxml::XPathError; end

    # Error raised when XPath syntax is invalid
    class SyntaxError < Error
      attr_reader :position, :token

      def initialize(message, expression: nil, position: nil, token: nil)
        @position = position
        @token = token
        super(message, expression: expression)
      end

      def to_s
        msg = super
        msg += "\n  Position: #{@position}" if @position
        msg += "\n  Unexpected token: #{@token.inspect}" if @token
        msg
      end
    end

    # Error raised when XPath evaluation fails
    class EvaluationError < Error
      attr_reader :context_node, :step

      def initialize(message, expression: nil, context_node: nil, step: nil)
        @context_node = context_node
        @step = step
        super(message, expression: expression)
      end

      def to_s
        msg = super
        msg += "\n  Context node: <#{@context_node.name}>" if @context_node.respond_to?(:name)
        msg += "\n  Step: #{@step}" if @step
        msg
      end
    end

    # Error raised when an XPath function is not found or invalid
    class FunctionError < Error
      attr_reader :function_name, :argument_count

      def initialize(message, expression: nil, function_name: nil,
argument_count: nil)
        @function_name = function_name
        @argument_count = argument_count
        super(message, expression: expression)
      end

      def to_s
        msg = super
        msg += "\n  Function: #{@function_name}" if @function_name
        msg += "\n  Arguments: #{@argument_count}" if @argument_count
        msg
      end
    end

    # Error raised when an XPath operation on unsupported node type
    class NodeTypeError < Error
      attr_reader :node_type, :operation

      def initialize(message, expression: nil, node_type: nil, operation: nil)
        @node_type = node_type
        @operation = operation
        super(message, expression: expression)
      end

      def to_s
        msg = super
        msg += "\n  Node type: #{@node_type}" if @node_type
        msg += "\n  Operation: #{@operation}" if @operation
        msg
      end
    end
  end
end
