# frozen_string_literal: true

module Moxml
  module XPath
    # XPath expression parser
    #
    # Implements a recursive descent parser for XPath 1.0 expressions.
    # Builds an Abstract Syntax Tree (AST) from tokenized input.
    #
    # Grammar (simplified XPath 1.0):
    #   expr        ::= or_expr
    #   or_expr     ::= and_expr ('or' and_expr)*
    #   and_expr    ::= equality ('and' equality)*
    #   equality    ::= relational (('=' | '!=') relational)*
    #   relational  ::= additive (('<' | '>' | '<=' | '>=') additive)*
    #   additive    ::= multiplicative (('+' | '-') multiplicative)*
    #   multiplicative ::= unary (('*' | 'div' | 'mod') unary)*
    #   unary       ::= ('-')? union
    #   union       ::= path_expr ('|' path_expr)*
    #   path_expr   ::= filter_expr | location_path
    #   filter_expr ::= primary_expr predicate*
    #   primary     ::= variable | '(' expr ')' | literal | number | function
    #   location_path ::= absolute_path | relative_path
    #
    # @example
    #   ast = Parser.parse("//book[@id='123']")
    #   ast = Parser.parse_with_cache("//book[@id='123']")
    class Parser
      # Parse cache for compiled expressions
      CACHE = Cache.new(100)

      # Parse an XPath expression
      #
      # @param expression [String] XPath expression to parse
      # @return [AST::Node] Root node of AST
      # @raise [XPath::SyntaxError] if expression is invalid
      def self.parse(expression)
        new(expression).parse
      end

      # Parse with caching
      #
      # @param expression [String] XPath expression to parse
      # @return [AST::Node] Root node of AST (possibly cached)
      def self.parse_with_cache(expression)
        CACHE.get_or_set(expression) { parse(expression) }
      end

      # Initialize parser with expression
      #
      # @param expression [String] XPath expression
      def initialize(expression)
        @expression = expression.to_s
        @lexer = Lexer.new(@expression)
        @tokens = @lexer.tokenize
        @position = 0
      end

      # Parse the expression into an AST
      #
      # @return [AST::Node] Root node of AST
      # @raise [XPath::SyntaxError] if expression is invalid
      def parse
        return AST::Node.new(:empty) if @tokens.empty?

        result = parse_expr

        unless at_end?
          raise_syntax_error("Unexpected token after expression: #{current_token}")
        end

        result
      end

      private

      # Get current token
      #
      # @return [Array, nil] Current token [type, value, position]
      def current_token
        @tokens[@position]
      end

      # Get current token type
      #
      # @return [Symbol, nil] Token type
      def current_type
        current_token&.first
      end

      # Get current token value
      #
      # @return [String, nil] Token value
      def current_value
        current_token&.[](1)
      end

      # Check if at end of tokens
      #
      # @return [Boolean]
      def at_end?
        @position >= @tokens.length
      end

      # Advance to next token
      #
      # @return [Array, nil] Previous token
      def advance
        token = current_token
        @position += 1
        token
      end

      # Check if current token matches type
      #
      # @param types [Array<Symbol>] Token types to check
      # @return [Boolean]
      def match?(*types)
        types.any?(current_type)
      end

      # Consume token if it matches, otherwise error
      #
      # @param type [Symbol] Expected token type
      # @param message [String] Error message if not found
      # @return [Array] Consumed token
      # @raise [XPath::SyntaxError] if token doesn't match
      def consume(type, message)
        if current_type == type
          advance
        else
          raise_syntax_error(message)
        end
      end

      # Raise syntax error
      #
      # @param message [String] Error message
      # @raise [XPath::SyntaxError]
      def raise_syntax_error(message)
        position = current_token&.[](2) || @expression.length
        raise XPath::SyntaxError.new(
          message,
          expression: @expression,
          position: position,
        )
      end

      # Parse top-level expression
      def parse_expr
        parse_or_expr
      end

      # Parse OR expression
      def parse_or_expr
        left = parse_and_expr

        while match?(:or)
          advance
          right = parse_and_expr
          left = AST::Node.binary_op(:or, left, right)
        end

        left
      end

      # Parse AND expression
      def parse_and_expr
        left = parse_equality

        while match?(:and)
          advance
          right = parse_equality
          left = AST::Node.binary_op(:and, left, right)
        end

        left
      end

      # Parse equality expression
      def parse_equality
        left = parse_relational

        while match?(:eq, :neq)
          op = current_type
          advance
          right = parse_relational
          left = AST::Node.binary_op(op, left, right)
        end

        left
      end

      # Parse relational expression
      def parse_relational
        left = parse_additive

        while match?(:lt, :gt, :lte, :gte)
          op = current_type
          advance
          right = parse_additive
          left = AST::Node.binary_op(op, left, right)
        end

        left
      end

      # Parse additive expression
      def parse_additive
        left = parse_multiplicative

        while match?(:plus, :minus)
          op = current_type
          advance
          right = parse_multiplicative
          left = AST::Node.binary_op(op, left, right)
        end

        left
      end

      # Parse multiplicative expression
      def parse_multiplicative
        left = parse_unary

        while match?(:star, :div, :mod)
          op = current_type
          advance
          right = parse_unary
          left = AST::Node.binary_op(op, left, right)
        end

        left
      end

      # Parse unary expression
      def parse_unary
        if match?(:minus)
          advance
          operand = parse_union
          return AST::Node.unary_op(:minus, operand)
        end

        parse_union
      end

      # Parse union expression
      def parse_union
        left = parse_path_expr

        if match?(:pipe)
          paths = [left]
          while match?(:pipe)
            advance
            paths << parse_path_expr
          end
          return AST::Node.union(*paths)
        end

        left
      end

      # Parse path expression (location path or filter expression)
      def parse_path_expr
        # Check for absolute path
        if match?(:slash, :dslash)
          return parse_location_path
        end

        # Check for primary expression (could be filter expression)
        if match?(:string, :number, :dollar, :lparen) ||
            (match?(:name) && peek_is?(:lparen))
          # Primary expression that could be filtered
          expr = parse_primary

          # Check for predicates (filter expression)
          if match?(:lbracket)
            predicates = []
            while match?(:lbracket)
              advance
              condition = parse_expr
              consume(:rbracket, "Expected ']' after predicate")
              predicates << AST::Node.predicate(condition)
            end
            expr = AST::Node.new(:filter_expr, [expr] + predicates)
          end

          return expr
        end

        # Otherwise, it's a location path
        parse_location_path
      end

      # Check if next token matches type
      def peek_is?(type)
        @tokens[@position + 1]&.first == type
      end

      # Parse location path
      def parse_location_path
        if match?(:slash)
          advance
          # Absolute path: /
          if at_end? || match?(:pipe, :rbracket, :rparen, :comma)
            return AST::Node.absolute_path(AST::Node.current)
          end

          # Absolute path with steps: /step1/step2
          steps = parse_relative_path
          return AST::Node.absolute_path(*steps.children)
        elsif match?(:dslash)
          advance
          # Descendant-or-self: //
          steps = parse_relative_path
          return AST::Node.absolute_path(
            AST::Node.axis("descendant-or-self", AST::Node.wildcard),
            *steps.children,
          )
        end

        # Relative path
        parse_relative_path
      end

      # Parse relative path (series of steps)
      def parse_relative_path
        steps = [parse_step]

        while match?(:slash) && !at_end?
          advance
          if match?(:slash)
            # Double slash within path
            advance
            steps << AST::Node.axis("descendant-or-self", AST::Node.wildcard)
          end
          steps << parse_step unless at_end? || match?(:pipe, :rbracket,
                                                       :rparen, :comma)
        end

        AST::Node.relative_path(*steps)
      end

      # Parse a single step
      def parse_step
        # Abbreviated steps
        if match?(:dot)
          advance
          return AST::Node.current
        elsif match?(:ddot)
          advance
          return AST::Node.parent
        elsif match?(:at)
          advance
          # Attribute: @name
          name = consume(:name, "Expected attribute name after @")
          node_test = AST::Node.test(nil, name[1])
          step = AST::Node.axis("attribute", node_test)
          return parse_predicates(step)
        end

        # Full axis step or abbreviated child step
        if match?(:axis)
          axis_name = current_value
          advance
          consume(:dcolon, "Expected '::' after axis name")
          node_test = parse_node_test
          step = AST::Node.axis(axis_name, node_test)
        else
          # Abbreviated child axis
          node_test = parse_node_test
          step = AST::Node.axis("child", node_test)
        end

        parse_predicates(step)
      end

      # Parse node test
      def parse_node_test
        if match?(:star)
          advance
          return AST::Node.wildcard
        elsif match?(:node_type)
          type_name = current_value
          advance
          consume(:lparen, "Expected '(' after node type")
          consume(:rparen, "Expected ')' after node type")
          return AST::Node.node_type(type_name)
        elsif match?(:name, :and, :or, :mod, :div)
          # Accept keywords as valid element names (they're valid XML names)
          name = current_value
          advance

          # Check for namespace prefix
          if match?(:colon) && !match?(:dcolon)
            advance
            if match?(:star)
              advance
              return AST::Node.test(name, "*")
            elsif match?(:name, :and, :or, :mod, :div)
              # Accept keywords as local names too
              local_name = current_value
              advance
              return AST::Node.test(name, local_name)
            else
              raise_syntax_error("Expected local name after namespace")
            end
          end

          return AST::Node.test(nil, name)
        end

        raise_syntax_error("Expected node test")
      end

      # Parse predicates
      def parse_predicates(step)
        predicates = []

        while match?(:lbracket)
          advance
          condition = parse_expr
          consume(:rbracket, "Expected ']' after predicate")
          predicates << AST::Node.predicate(condition)
        end

        return step if predicates.empty?

        # Attach predicates to step
        AST::Node.new(:step_with_predicates, [step] + predicates)
      end

      # Parse primary expression
      def parse_primary
        if match?(:string)
          value = current_value
          advance
          return AST::Node.string(value)
        elsif match?(:number)
          value = current_value
          advance
          return AST::Node.number(value)
        elsif match?(:dollar)
          advance
          name = consume(:name, "Expected variable name after $")
          return AST::Node.variable(name[1])
        elsif match?(:lparen)
          advance
          expr = parse_expr
          consume(:rparen, "Expected ')' after expression")
          return expr
        elsif match?(:name)
          name = current_value
          advance

          # Check for function call
          if match?(:lparen)
            advance
            args = []

            unless match?(:rparen)
              args << parse_expr
              while match?(:comma)
                advance
                args << parse_expr
              end
            end

            consume(:rparen, "Expected ')' after function arguments")
            return AST::Node.function(name, *args)
          end

          # Just a name without function call - shouldn't happen in parse_primary
          # but return it as a relative path
          @position -= 1 # Put the name back
          return parse_location_path
        end

        raise_syntax_error("Expected primary expression")
      end
    end
  end
end
