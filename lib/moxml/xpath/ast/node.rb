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
          "#<#{self.class.name}>"
        end

        alias to_s inspect
      end
    end
  end
end
