# frozen_string_literal: true

module Moxml
  module XPath
    autoload :Engine, "moxml/xpath/engine"
    autoload :Context, "moxml/xpath/context"
    autoload :Conversion, "moxml/xpath/conversion"
    autoload :Cache, "moxml/xpath/cache"
    autoload :Lexer, "moxml/xpath/lexer"
    autoload :Parser, "moxml/xpath/parser"
    autoload :Compiler, "moxml/xpath/compiler"
    autoload :Ordering, "moxml/xpath/ordering"

    autoload :Error, "moxml/xpath/errors"
    autoload :SyntaxError, "moxml/xpath/errors"
    autoload :EvaluationError, "moxml/xpath/errors"
    autoload :FunctionError, "moxml/xpath/errors"
    autoload :NodeTypeError, "moxml/xpath/errors"
    autoload :InvalidContextError, "moxml/xpath/errors"

    module AST
      autoload :Node, "moxml/xpath/ast/node"
    end

    module Ruby
      autoload :Node, "moxml/xpath/ruby/node"
      autoload :Generator, "moxml/xpath/ruby/generator"
    end

    module_function

    # Evaluate an expression through the pure-Ruby XPath 1.0 engine —
    # the model's reference lane. Adapters route shapes their native
    # engine cannot answer here (the `xmlns:` idiom, `text()` node
    # tests, ...). Returns the engine's answer: an Array of wrapped
    # nodes in document order, a NodeSet, or a scalar.
    def evaluate(node, expression, namespaces = {}, adapter: nil)
      context = node.is_a?(Moxml::Node) ? node.context : ::Moxml::Context.new(adapter)
      wrapped = node.is_a?(Moxml::Node) ? node : Moxml::Node.wrap(node, context)
      compiled = Compiler.compile_with_cache(Parser.parse(expression),
                                             namespaces: namespaces)
      compiled.call(wrapped)
    end

    # The adapter-contract form of #evaluate: Array<native> | scalar.
    def evaluate_natives(node, expression, namespaces = {}, adapter: nil)
      result = evaluate(node, expression, namespaces, adapter: adapter)
      case result
      when Array
        result.map { |n| n.is_a?(Moxml::Node) ? n.native : n }
      when NodeSet
        result.to_a.map(&:native)
      else
        result
      end
    end
  end
end
