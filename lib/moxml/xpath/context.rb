# frozen_string_literal: true

module Moxml
  module XPath
    # Class used as the context for compiled XPath Procs.
    #
    # The binding of this class is used for the binding of Procs compiled by
    # {Compiler}. Not using a specific binding would result in the procs using
    # the binding of {Compiler#compile}, which could lead to race conditions.
    #
    # @private
    class Context
      def initialize
        @binding = binding
      end

      # Evaluates a Ruby code string in this context's binding.
      #
      # @param [String] string Ruby code to evaluate
      # @return [Proc]
      def evaluate(string)
        @binding.eval(string)
      end
    end
  end
end
