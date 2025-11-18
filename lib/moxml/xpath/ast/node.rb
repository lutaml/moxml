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
        # @param value [Object] Optional value for leaf nodes
        def initialize(type = :node, children = [], value = nil)
          @type = type
          @children = Array(children)
          @value = value
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
            "#<#{self.class.name} @type=#{@type} @value=#{@value.inspect}>"
          elsif @children.any?
            "#<#{self.class.name} @type=#{@type} children=#{@children.size}>"
          else
            "#<#{self.class.name} @type=#{@type}>"
          end
        end

        alias to_s inspect

        # Factory methods for creating specific node types

        # Create an absolute path node (starts with / or //)
        def self.absolute_path(descendant_or_self, *steps)
          new(:absolute_path, [descendant_or_self] + steps)
        end

        # Create a relative path node
        def self.relative_path(*steps)
          new(:relative_path, steps)
        end

        # Create a path node
        def self.path(*steps)
          new(:path, steps)
        end

        # Create an axis node
        def self.axis(axis_name, node_test, *predicates)
          new(:axis, [axis_name, node_test] + predicates)
        end

        # Create a node test
        def self.test(namespace, name)
          new(:test, [], { namespace: namespace, name: name })
        end

        # Create a wildcard test
        def self.wildcard
          new(:wildcard)
        end

        # Create a predicate node
        def self.predicate(condition)
          new(:predicate, [condition])
        end

        # Create a function call node
        def self.function(name, *args)
          new(:function, args, name)
        end

        # Create a variable reference node
        def self.variable(name)
          new(:variable, [], name)
        end

        # Create a literal string node
        def self.string(value)
          new(:string, [], value)
        end

        # Create a literal number node
        def self.number(value)
          new(:number, [], value.to_f)
        end

        # Create a binary operator node
        def self.binary_op(operator, left, right)
          new(:binary_op, [left, right], operator)
        end

        # Create a unary operator node
        def self.unary_op(operator, operand)
          new(:unary_op, [operand], operator)
        end

        # Create a union node (|)
        def self.union(*expressions)
          new(:union, expressions)
        end

        # Create an attribute node
        def self.attribute(name)
          new(:attribute, [], name)
        end

        # Create a current node (.)
        def self.current
          new(:current)
        end

        # Create a parent node (..)
        def self.parent
          new(:parent)
        end

        # Create a node type test (text(), comment(), etc.)
        def self.node_type(type_name)
          new(:node_type, [], type_name)
        end
      end
    end
  end
end
