# frozen_string_literal: true

module Moxml
  # XPath 1.0 implementation for Moxml
  #
  # This module provides a complete XPath 1.0 engine for querying XML
  # documents, particularly for the Ox adapter which has limited native
  # XPath support.
  #
  # @example Basic usage
  #   engine = Moxml::XPath::Engine.new(document)
  #   results = engine.evaluate("//book[@id='123']")
  #
  module XPath
    autoload :Engine, "moxml/xpath/engine"
    autoload :Compiler, "moxml/xpath/compiler"
    autoload :Parser, "moxml/xpath/parser"
    autoload :Lexer, "moxml/xpath/lexer"
    autoload :Cache, "moxml/xpath/cache"
    autoload :Context, "moxml/xpath/context"
    autoload :Conversion, "moxml/xpath/conversion"

    # Require errors directly so classes are immediately available
    require_relative "xpath/errors"

    # AST nodes for expression representation
    module AST
      autoload :Node, "moxml/xpath/ast/node"
    end

    # Ruby AST nodes for code generation
    module Ruby
      autoload :Node, "moxml/xpath/ruby/node"
      autoload :Generator, "moxml/xpath/ruby/generator"
    end
  end
end
