# frozen_string_literal: true

module Moxml
  module XPath
    # XPath expression lexer/tokenizer
    #
    # Converts XPath expressions into a stream of tokens for parsing.
    # Each token is represented as [type, value, position].
    #
    # @example
    #   lexer = Lexer.new("//book[@id='123']")
    #   tokens = lexer.tokenize
    #   # => [[:dslash, "//", 0], [:name, "book", 2], ...]
    class Lexer
      # XPath axis names for recognition
      AXIS_NAMES = %w[
        ancestor ancestor-or-self attribute child descendant
        descendant-or-self following following-sibling namespace
        parent preceding preceding-sibling self
      ].freeze

      # XPath node type names
      NODE_TYPES = %w[
        comment text processing-instruction node
      ].freeze

      # Reserved keywords
      KEYWORDS = %w[and or mod div].freeze

      # Initialize lexer with XPath expression
      #
      # @param expression [String] XPath expression to tokenize
      def initialize(expression)
        @expression = expression.to_s
        @position = 0
        @length = @expression.length
        @tokens = []
      end

      # Tokenize the XPath expression
      #
      # @return [Array<Array>] Array of [type, value, position] tuples
      # @raise [XPath::SyntaxError] if expression contains invalid syntax
      def tokenize
        @tokens = []
        @position = 0

        while @position < @length
          skip_whitespace
          break if @position >= @length

          token_start = @position

          case current_char
          when "/"
            if peek_char == "/"
              add_token(:dslash, "//", token_start)
              advance(2)
            else
              add_token(:slash, "/", token_start)
              advance
            end
          when "|"
            add_token(:pipe, "|", token_start)
            advance
          when "+"
            add_token(:plus, "+", token_start)
            advance
          when "-"
            add_token(:minus, "-", token_start)
            advance
          when "*"
            add_token(:star, "*", token_start)
            advance
          when "="
            add_token(:eq, "=", token_start)
            advance
          when "!"
            if peek_char == "="
              add_token(:neq, "!=", token_start)
              advance(2)
            else
              raise_syntax_error("Unexpected '!' at position #{@position}")
            end
          when "<"
            if peek_char == "="
              add_token(:lte, "<=", token_start)
              advance(2)
            else
              add_token(:lt, "<", token_start)
              advance
            end
          when ">"
            if peek_char == "="
              add_token(:gte, ">=", token_start)
              advance(2)
            else
              add_token(:gt, ">", token_start)
              advance
            end
          when "("
            add_token(:lparen, "(", token_start)
            advance
          when ")"
            add_token(:rparen, ")", token_start)
            advance
          when "["
            add_token(:lbracket, "[", token_start)
            advance
          when "]"
            add_token(:rbracket, "]", token_start)
            advance
          when ","
            add_token(:comma, ",", token_start)
            advance
          when "@"
            add_token(:at, "@", token_start)
            advance
          when ":"
            if peek_char == ":"
              add_token(:dcolon, "::", token_start)
              advance(2)
            else
              add_token(:colon, ":", token_start)
              advance
            end
          when "."
            if peek_char == "."
              add_token(:ddot, "..", token_start)
              advance(2)
            elsif /\d/.match?(peek_char)
              scan_number(token_start)
            else
              add_token(:dot, ".", token_start)
              advance
            end
          when "$"
            add_token(:dollar, "$", token_start)
            advance
          when '"', "'"
            scan_string(token_start)
          when /\d/
            scan_number(token_start)
          when /[a-zA-Z_]/
            scan_name_or_keyword(token_start)
          else
            raise_syntax_error(
              "Unexpected character '#{current_char}' at position #{@position}",
            )
          end
        end

        @tokens
      end

      private

      # Get current character
      #
      # @return [String, nil] Current character or nil if at end
      def current_char
        @expression[@position]
      end

      # Peek at next character
      #
      # @return [String, nil] Next character or nil if at end
      def peek_char
        @expression[@position + 1]
      end

      # Advance position by n characters
      #
      # @param n [Integer] Number of characters to advance
      def advance(n = 1)
        @position += n
      end

      # Skip whitespace characters
      def skip_whitespace
        @position += 1 while @position < @length &&
            @expression[@position] =~ /\s/
      end

      # Add token to token list
      #
      # @param type [Symbol] Token type
      # @param value [String] Token value
      # @param position [Integer] Token position
      def add_token(type, value, position)
        @tokens << [type, value, position]
      end

      # Scan string literal
      #
      # @param start_pos [Integer] Starting position
      def scan_string(start_pos)
        quote = current_char
        advance

        value = ""
        while @position < @length && current_char != quote
          if current_char == "\\"
            advance
            if @position < @length
              # Handle escape sequences
              value += case current_char
                       when "t"
                         "\t"
                       when "n"
                         "\n"
                       when "r"
                         "\r"
                       when "\\"
                         "\\"
                       when '"'
                         '"'
                       when "'"
                         "'"
                       else
                         # Unknown escape - add literally
                         current_char
                       end
            end
          else
            value += current_char
          end
          advance
        end

        if @position >= @length
          raise_syntax_error("Unterminated string starting at position #{start_pos}")
        end

        advance # Skip closing quote
        add_token(:string, value, start_pos)
      end

      # Scan number (integer or decimal)
      #
      # @param start_pos [Integer] Starting position
      def scan_number(start_pos)
        value = ""

        # Integer part
        while @position < @length && current_char =~ /\d/
          value += current_char
          advance
        end

        # Decimal part
        if @position < @length && current_char == "."
          value += current_char
          advance

          while @position < @length && current_char =~ /\d/
            value += current_char
            advance
          end
        end

        add_token(:number, value, start_pos)
      end

      # Scan name or keyword
      #
      # @param start_pos [Integer] Starting position
      def scan_name_or_keyword(start_pos)
        value = ""

        # Name can contain letters, digits, underscores, hyphens, and dots
        while @position < @length && current_char =~ /[a-zA-Z0-9_\-.]/
          value += current_char
          advance
        end

        # Check if it's an axis name followed by ::
        if AXIS_NAMES.include?(value) &&
            @position < @length - 1 &&
            @expression[@position, 2] == "::"
          add_token(:axis, value, start_pos)
        elsif KEYWORDS.include?(value)
          add_token(value.to_sym, value, start_pos)
        elsif NODE_TYPES.include?(value)
          add_token(:node_type, value, start_pos)
        else
          add_token(:name, value, start_pos)
        end
      end

      # Raise syntax error
      #
      # @param message [String] Error message
      # @raise [XPath::SyntaxError]
      def raise_syntax_error(message)
        raise Moxml::XPath::SyntaxError.new(
          message,
          expression: @expression,
          position: @position,
        )
      end
    end
  end
end
