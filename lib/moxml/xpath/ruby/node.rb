# frozen_string_literal: true

module Moxml
  module XPath
    module Ruby
      # Class representing a single node in a Ruby AST.
      #
      # This class provides a fluent DSL for building Ruby code dynamically.
      # It's modeled after the "ast" gem but simplified to avoid method conflicts.
      #
      # @example Building an if statement
      #   number1 = Node.new(:lit, ['10'])
      #   number2 = Node.new(:lit, ['20'])
      #
      #   (number2 > number1).if_true do
      #     Node.new(:lit, ['30'])
      #   end
      #
      # @private
      class Node < BasicObject
        undef_method :!, :!=

        # @return [Symbol]
        attr_reader :type

        # @param [Symbol] type The type of AST node
        # @param [Array] children Child nodes or values
        def initialize(type, children = [])
          @type = type.to_sym
          @children = children
        end

        # @return [Array]
        def to_a
          @children
        end
        alias to_ary to_a

        # Returns a "to_a" call node.
        #
        # @return [Moxml::XPath::Ruby::Node]
        def to_array
          Node.new(:send, [self, :to_a])
        end

        # Returns an assignment node.
        #
        # Wraps assigned values in a begin/end block to ensure that
        # multiple lines of code result in the proper value being assigned.
        #
        # @param [Moxml::XPath::Ruby::Node] other
        # @return [Moxml::XPath::Ruby::Node]
        def assign(other)
          other = other.wrap if other.type == :followed_by

          Node.new(:assign, [self, other])
        end

        # Returns an equality expression node.
        #
        # @param [Moxml::XPath::Ruby::Node] other
        # @return [Moxml::XPath::Ruby::Node]
        def eq(other)
          Node.new(:eq, [self, other])
        end

        # Returns a boolean "and" node.
        #
        # @param [Moxml::XPath::Ruby::Node] other
        # @return [Moxml::XPath::Ruby::Node]
        def and(other)
          Node.new(:and, [self, other])
        end

        # Returns a boolean "or" node.
        #
        # @param [Moxml::XPath::Ruby::Node] other
        # @return [Moxml::XPath::Ruby::Node]
        def or(other)
          Node.new(:or, [self, other])
        end

        # Returns a node that evaluates to its inverse.
        #
        # @example
        #   foo.not # => !foo
        #
        # @return [Moxml::XPath::Ruby::Node]
        def not
          !self
        end

        # Returns a node for Ruby's "is_a?" method.
        #
        # @param [Class] klass
        # @return [Moxml::XPath::Ruby::Node]
        def is_a?(klass)
          # If klass is already a Node (e.g., a const node), use it directly
          # Otherwise wrap it in a lit node
          klass_node = if klass.respond_to?(:type)
                         klass
                       else
                         Node.new(:lit, [klass.to_s])
                       end

          Node.new(:send, [self, "is_a?", klass_node])
        end

        # Wraps the current node in a block.
        #
        # @param [Array] args Arguments (as Node instances) to pass to the block
        # @return [Moxml::XPath::Ruby::Node]
        def add_block(*args)
          Node.new(:block, [self, args, yield])
        end

        # Wraps the current node in a `begin` node.
        #
        # @return [Moxml::XPath::Ruby::Node]
        def wrap
          Node.new(:begin, [self])
        end

        # Wraps the current node in an if statement node.
        #
        # The body of this statement is set to the return value of the supplied
        # block.
        #
        # @return [Moxml::XPath::Ruby::Node]
        def if_true
          Node.new(:if, [self, yield])
        end

        # Wraps the current node in an `if !...` statement.
        #
        # @see [#if_true]
        def if_false(&block)
          self.not.if_true(&block)
        end

        # Wraps the current node in a `while` statement.
        #
        # The body of this statement is set to the return value of the supplied
        # block.
        #
        # @return [Moxml::XPath::Ruby::Node]
        def while_true
          Node.new(:while, [self, yield])
        end

        # Adds an "else" statement to the current node.
        #
        # This method assumes it's being called only on "if" nodes.
        #
        # @return [Moxml::XPath::Ruby::Node]
        def else
          Node.new(:if, @children + [yield])
        end

        # Chains two nodes together.
        #
        # @param [Moxml::XPath::Ruby::Node] other
        # @return [Moxml::XPath::Ruby::Node]
        def followed_by(other = nil)
          other = yield if ::Kernel.block_given?

          Node.new(:followed_by, [self, other])
        end

        # Returns a node for a method call.
        #
        # @param [Symbol] name The name of the method to call
        # @param [Array] args Any arguments (as Node instances) to pass
        # @return [Moxml::XPath::Ruby::Node]
        def method_missing(name, *args)
          Node.new(:send, [self, name.to_s, *args])
        end

        # Prevent implicit string conversion - Nodes must be explicitly processed
        def to_str
          ::Kernel.raise ::TypeError, "Cannot implicitly

 convert #{self.class} to String. Use Generator#process instead."
        end

        # @return [String]
        def inspect
          "(#{type} #{@children.map(&:inspect).join(' ')})"
        end
      end
    end
  end
end
