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
    autoload :Context, "moxml/xpath/context"
    autoload :Conversion, "moxml/xpath/conversion"
    autoload :Cache, "moxml/xpath/cache"
    autoload :Lexer, "moxml/xpath/lexer"
    autoload :Parser, "moxml/xpath/parser"
    autoload :Compiler, "moxml/xpath/compiler"

    # Require errors directly so classes are immediately available
    require_relative "xpath/errors"

    # AST nodes for expression representation
    module AST
      autoload :Node, "moxml/xpath/ast/node"
    end

    # Ruby AST generation for compiling XPath
    module Ruby
      autoload :Node, "moxml/xpath/ruby/node"
      autoload :Generator, "moxml/xpath/ruby/generator"
    end
  end
end
