# frozen_string_literal: true

module Moxml
  # Base error class for all Moxml errors
  class Error < StandardError; end

  # Error raised when parsing XML fails
  class ParseError < Error
    attr_reader :line, :column, :source

    def initialize(message, line: nil, column: nil, source: nil)
      @line = line
      @column = column
      @source = source
      super(message)
    end

    def to_s
      msg = super
      msg += "\n  Line: #{@line}" if @line
      msg += "\n  Column: #{@column}" if @column
      msg += "\n  Source: #{@source.inspect}" if @source
      msg += "\n  Hint: Check XML syntax and ensure all tags are properly closed"
      msg
    end
  end

  # Error raised when XPath expression evaluation fails
  class XPathError < Error
    attr_reader :expression, :adapter, :node

    def initialize(message, expression: nil, adapter: nil, node: nil)
      @expression = expression
      @adapter = adapter
      @node = node
      super(message)
    end

    def to_s
      msg = super
      msg += "\n  Expression: #{@expression}" if @expression
      msg += "\n  Adapter: #{@adapter}" if @adapter
      msg += "\n  Node: <#{@node.name}>" if @node.is_a?(Element) || @node.is_a?(Attribute)
      msg += "\n  Hint: Verify XPath syntax and ensure the adapter supports the expression"
      msg
    end
  end

  # Error raised when XML validation fails
  class ValidationError < Error
    attr_reader :node, :constraint, :value

    def initialize(message, node: nil, constraint: nil, value: nil)
      @node = node
      @constraint = constraint
      @value = value
      super(message)
    end

    def to_s
      msg = super
      # Only add extra details if any were provided
      has_details = (@node.is_a?(Element) || @node.is_a?(Attribute)) || @constraint || @value
      if has_details
        msg += "\n  Node: <#{@node.name}>" if @node.is_a?(Element) || @node.is_a?(Attribute)
        msg += "\n  Constraint: #{@constraint}" if @constraint
        msg += "\n  Value: #{@value.inspect}" if @value
        msg += "\n  Hint: Ensure the value meets XML specification requirements"
      end
      msg
    end
  end

  # Error raised when namespace operations fail
  class NamespaceError < Error
    attr_reader :prefix, :uri, :element

    def initialize(message, prefix: nil, uri: nil, element: nil)
      @prefix = prefix
      @uri = uri
      @element = element
      super(message)
    end
  end

  # Error raised when adapter operations fail
  class AdapterError < Error
    attr_reader :adapter_name, :operation, :native_error

    def initialize(message, adapter: nil, operation: nil, native_error: nil)
      @adapter_name = adapter
      @operation = operation
      @native_error = native_error
      super(message)
    end

    def to_s
      msg = super
      msg += "\n  Adapter: #{@adapter_name}" if @adapter_name
      msg += "\n  Operation: #{@operation}" if @operation
      if @native_error
        msg += "\n  Native Error: #{@native_error.class.name}: #{@native_error.message}"
      end
      msg += "\n  Hint: Ensure the adapter gem is properly installed and compatible"
      msg
    end
  end

  # Error raised when serialization fails
  class SerializationError < Error
    attr_reader :node, :adapter, :format

    def initialize(message, node: nil, adapter: nil, format: nil)
      @node = node
      @adapter = adapter
      @format = format
      super(message)
    end

    def to_s
      msg = super
      msg += "\n  Node: <#{@node.name}>" if @node.is_a?(Element) || @node.is_a?(Attribute)
      msg += "\n  Adapter: #{@adapter}" if @adapter
      msg += "\n  Format: #{@format}" if @format
      msg += "\n  Hint: Check that the node structure is valid for serialization"
      msg
    end
  end

  # Error raised when document structure is invalid
  class DocumentStructureError < Error
    attr_reader :attempted_operation, :current_state

    def initialize(message, operation: nil, state: nil)
      @attempted_operation = operation
      @current_state = state
      super(message)
    end

    def to_s
      msg = super
      msg += "\n  Operation: #{@attempted_operation}" if @attempted_operation
      msg += "\n  Current State: #{@current_state}" if @current_state
      msg += "\n  Hint: Ensure the document structure follows XML specifications"
      msg
    end
  end

  # Error raised when attribute operations fail
  class AttributeError < Error
    attr_reader :attribute_name, :element, :value

    def initialize(message, name: nil, element: nil, value: nil)
      @attribute_name = name
      @element = element
      @value = value
      super(message)
    end

    def to_s
      msg = super
      msg += "\n  Attribute: #{@attribute_name}" if @attribute_name
      msg += "\n  Element: <#{@element.name}>" if @element.is_a?(Element)
      msg += "\n  Value: #{@value.inspect}" if @value
      msg += "\n  Hint: Verify attribute name follows XML naming rules"
      msg
    end
  end

  # Error raised when a feature is not implemented by an adapter
  class NotImplementedError < Error
    attr_reader :feature, :adapter

    def initialize(message = nil, feature: nil, adapter: nil)
      @feature = feature
      @adapter = adapter
      message ||= "Feature not implemented"
      super(message)
    end

    def to_s
      msg = super
      msg += "\n  Feature: #{@feature}" if @feature
      msg += "\n  Adapter: #{@adapter}" if @adapter
      msg += "\n  Hint: This feature may not be supported by the current adapter"
      msg
    end
  end
end
