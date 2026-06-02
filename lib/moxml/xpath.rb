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
  end
end
