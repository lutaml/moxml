# frozen_string_literal: true

module Moxml
  module XPath
    module AST
      # Abstract base class for all XPath AST nodes
      #
      # All AST nodes must implement the #evaluate method which takes
      # a context and returns a result (NodeSet, String, Number, or Boolean).
      #
      # @abstract Subclass and override {#evaluate} to implement
      class Node
        attr_reader :type, :children, :value

        # Initialize a new AST node
        #
        # @param type [Symbol] Node type
        # @param children [Array] Child nodes
        # @param value [Object] Node value
        def initialize(type = :unknown, children = [], value = nil)
          @type = type
          @children = children
          @value = value
        end

        # Factory Methods

        # Create a test node (name test)
        def self.test(namespace, name)
          new(:test, [], { namespace: namespace, name: name })
        end

        # Create a wildcard node (*)
        def self.wildcard
          new(:wildcard)
        end

        # Create an axis node
        def self.axis(name, node_test, *predicates)
          new(:axis, [name, node_test, *predicates])
        end

        # Create a current node (.)
        def self.current
          new(:current)
        end

        # Create a parent node (..)
        def self.parent
          new(:parent)
        end

        # Create a string literal node
        def self.string(value)
          new(:string, [], value)
        end

        # Create a number literal node
        def self.number(value)
          new(:number, [], value)
        end

        # Create a variable node ($var)
        def self.variable(name)
          new(:var, [name])
        end

        # Create a function call node
        def self.function(name, *args)
          new(:call, [name, *args])
        end

        # Create a node type test (text(), comment(), etc.)
        def self.node_type(type_name)
          new(:node_type, [], type_name)
        end

        # Create a binary operator node
        def self.binary_op(op, left, right)
          new(op, [left, right])
        end

        # Create a unary operator node
        def self.unary_op(op, operand)
          new(op, [operand])
        end

        # Create a union node (|)
        def self.union(*paths)
          new(:pipe, paths)
        end

        # Create a predicate node ([expr])
        def self.predicate(condition)
          new(:predicate, [condition])
        end

        # Create an absolute path node (/)
        def self.absolute_path(*steps)
          new(:absolute_path, steps)
        end

        # Create a relative path node
        def self.relative_path(*steps)
          new(:relative_path, steps)
        end

        # Evaluate this AST node in the given context
        #
        # @param context [Moxml::XPath::Context] Evaluation context
        # @return [Moxml::NodeSet, String, Numeric, Boolean] Result of evaluation
        # @raise [NotImplementedError] if not overridden by subclass
        def evaluate(context)
          raise ::NotImplementedError,
                "#{self.class}#evaluate must be implemented by subclass"
        end

        # Check if this node is a constant value
        #
        # @return [Boolean] true if node represents a constant value
        def constant?
          false
        end

        # Get the result type of this node
        #
        # @return [Symbol] One of :node_set, :string, :number, :boolean
        def result_type
          :unknown
        end

        # String representation for debugging
        #
        # @return [String] Debug representation
        def inspect
          if @value
            "#<#{self.class.name} type=#{@type} value=#{@value.inspect}>"
          elsif @children.empty?
            "#<#{self.class.name} type=#{@type}>"
          else
            "#<#{self.class.name} type=#{@type} children=#{@children.size}>"
          end
        end

        alias to_s inspect
      end
    end
  end
end
