# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::XPath::Lexer do
  describe "#tokenize" do
    context "operators" do
      it "tokenizes single slash" do
        tokens = described_class.new("/").tokenize
        expect(tokens).to eq([[:slash, "/", 0]])
      end

      it "tokenizes double slash" do
        tokens = described_class.new("//").tokenize
        expect(tokens).to eq([[:dslash, "//", 0]])
      end

      it "tokenizes pipe" do
        tokens = described_class.new("|").tokenize
        expect(tokens).to eq([[:pipe, "|", 0]])
      end

      it "tokenizes plus" do
        tokens = described_class.new("+").tokenize
        expect(tokens).to eq([[:plus, "+", 0]])
      end

      it "tokenizes minus" do
        tokens = described_class.new("-").tokenize
        expect(tokens).to eq([[:minus, "-", 0]])
      end

      it "tokenizes star" do
        tokens = described_class.new("*").tokenize
        expect(tokens).to eq([[:star, "*", 0]])
      end

      it "tokenizes equals" do
        tokens = described_class.new("=").tokenize
        expect(tokens).to eq([[:eq, "=", 0]])
      end

      it "tokenizes not equals" do
        tokens = described_class.new("!=").tokenize
        expect(tokens).to eq([[:neq, "!=", 0]])
      end

      it "tokenizes less than" do
        tokens = described_class.new("<").tokenize
        expect(tokens).to eq([[:lt, "<", 0]])
      end

      it "tokenizes greater than" do
        tokens = described_class.new(">").tokenize
        expect(tokens).to eq([[:gt, ">", 0]])
      end

      it "tokenizes less than or equal" do
        tokens = described_class.new("<=").tokenize
        expect(tokens).to eq([[:lte, "<=", 0]])
      end

      it "tokenizes greater than or equal" do
        tokens = described_class.new(">=").tokenize
        expect(tokens).to eq([[:gte, ">=", 0]])
      end
    end

    context "delimiters" do
      it "tokenizes left parenthesis" do
        tokens = described_class.new("(").tokenize
        expect(tokens).to eq([[:lparen, "(", 0]])
      end

      it "tokenizes right parenthesis" do
        tokens = described_class.new(")").tokenize
        expect(tokens).to eq([[:rparen, ")", 0]])
      end

      it "tokenizes left bracket" do
        tokens = described_class.new("[").tokenize
        expect(tokens).to eq([[:lbracket, "[", 0]])
      end

      it "tokenizes right bracket" do
        tokens = described_class.new("]").tokenize
        expect(tokens).to eq([[:rbracket, "]", 0]])
      end

      it "tokenizes comma" do
        tokens = described_class.new(",").tokenize
        expect(tokens).to eq([[:comma, ",", 0]])
      end

      it "tokenizes at sign" do
        tokens = described_class.new("@").tokenize
        expect(tokens).to eq([[:at, "@", 0]])
      end

      it "tokenizes single colon" do
        tokens = described_class.new(":").tokenize
        expect(tokens).to eq([[:colon, ":", 0]])
      end

      it "tokenizes double colon" do
        tokens = described_class.new("::").tokenize
        expect(tokens).to eq([[:dcolon, "::", 0]])
      end

      it "tokenizes dot" do
        tokens = described_class.new(".").tokenize
        expect(tokens).to eq([[:dot, ".", 0]])
      end

      it "tokenizes double dot" do
        tokens = described_class.new("..").tokenize
        expect(tokens).to eq([[:ddot, "..", 0]])
      end

      it "tokenizes dollar sign" do
        tokens = described_class.new("$").tokenize
        expect(tokens).to eq([[:dollar, "$", 0]])
      end
    end

    context "keywords" do
      it 'tokenizes "and" keyword' do
        tokens = described_class.new("and").tokenize
        expect(tokens).to eq([[:and, "and", 0]])
      end

      it 'tokenizes "or" keyword' do
        tokens = described_class.new("or").tokenize
        expect(tokens).to eq([[:or, "or", 0]])
      end

      it 'tokenizes "mod" keyword' do
        tokens = described_class.new("mod").tokenize
        expect(tokens).to eq([[:mod, "mod", 0]])
      end

      it 'tokenizes "div" keyword' do
        tokens = described_class.new("div").tokenize
        expect(tokens).to eq([[:div, "div", 0]])
      end
    end

    context "axis names" do
      it "tokenizes child axis" do
        tokens = described_class.new("child::").tokenize
        expect(tokens).to eq([[:axis, "child", 0], [:dcolon, "::", 5]])
      end

      it "tokenizes descendant axis" do
        tokens = described_class.new("descendant::").tokenize
        expect(tokens).to eq([[:axis, "descendant", 0], [:dcolon, "::", 10]])
      end

      it "tokenizes ancestor-or-self axis" do
        tokens = described_class.new("ancestor-or-self::").tokenize
        expect(tokens).to eq([[:axis, "ancestor-or-self", 0],
                              [:dcolon, "::", 16]])
      end

      it "tokenizes following-sibling axis" do
        tokens = described_class.new("following-sibling::").tokenize
        expect(tokens).to eq([[:axis, "following-sibling", 0],
                              [:dcolon, "::", 17]])
      end

      it "treats axis name without :: as regular name" do
        tokens = described_class.new("child").tokenize
        expect(tokens).to eq([[:name, "child", 0]])
      end
    end

    context "node types" do
      it "tokenizes text() node type" do
        tokens = described_class.new("text").tokenize
        expect(tokens).to eq([[:node_type, "text", 0]])
      end

      it "tokenizes comment() node type" do
        tokens = described_class.new("comment").tokenize
        expect(tokens).to eq([[:node_type, "comment", 0]])
      end

      it "tokenizes node() node type" do
        tokens = described_class.new("node").tokenize
        expect(tokens).to eq([[:node_type, "node", 0]])
      end

      it "tokenizes processing-instruction() node type" do
        tokens = described_class.new("processing-instruction").tokenize
        expect(tokens).to eq([[:node_type, "processing-instruction", 0]])
      end
    end

    context "strings" do
      it "tokenizes double-quoted string" do
        tokens = described_class.new('"hello"').tokenize
        expect(tokens).to eq([[:string, "hello", 0]])
      end

      it "tokenizes single-quoted string" do
        tokens = described_class.new("'world'").tokenize
        expect(tokens).to eq([[:string, "world", 0]])
      end

      it "tokenizes empty string" do
        tokens = described_class.new('""').tokenize
        expect(tokens).to eq([[:string, "", 0]])
      end

      it "tokenizes string with spaces" do
        tokens = described_class.new('"hello world"').tokenize
        expect(tokens).to eq([[:string, "hello world", 0]])
      end

      it "tokenizes string with escaped quote" do
        tokens = described_class.new('"hello\\"world"').tokenize
        expect(tokens).to eq([[:string, 'hello"world', 0]])
      end

      it "raises error for unterminated string" do
        expect { described_class.new('"hello').tokenize }
          .to raise_error(Moxml::XPath::SyntaxError, /Unterminated string/)
      end
    end

    context "numbers" do
      it "tokenizes integer" do
        tokens = described_class.new("123").tokenize
        expect(tokens).to eq([[:number, "123", 0]])
      end

      it "tokenizes decimal" do
        tokens = described_class.new("123.45").tokenize
        expect(tokens).to eq([[:number, "123.45", 0]])
      end

      it "tokenizes number starting with dot" do
        tokens = described_class.new(".5").tokenize
        expect(tokens).to eq([[:number, ".5", 0]])
      end

      it "tokenizes zero" do
        tokens = described_class.new("0").tokenize
        expect(tokens).to eq([[:number, "0", 0]])
      end

      it "tokenizes large number" do
        tokens = described_class.new("999999").tokenize
        expect(tokens).to eq([[:number, "999999", 0]])
      end
    end

    context "names" do
      it "tokenizes simple name" do
        tokens = described_class.new("book").tokenize
        expect(tokens).to eq([[:name, "book", 0]])
      end

      it "tokenizes name with underscore" do
        tokens = described_class.new("my_element").tokenize
        expect(tokens).to eq([[:name, "my_element", 0]])
      end

      it "tokenizes name with hyphen" do
        tokens = described_class.new("my-element").tokenize
        expect(tokens).to eq([[:name, "my-element", 0]])
      end

      it "tokenizes name with dot" do
        tokens = described_class.new("my.element").tokenize
        expect(tokens).to eq([[:name, "my.element", 0]])
      end

      it "tokenizes name with numbers" do
        tokens = described_class.new("element123").tokenize
        expect(tokens).to eq([[:name, "element123", 0]])
      end

      it "tokenizes uppercase name" do
        tokens = described_class.new("BOOK").tokenize
        expect(tokens).to eq([[:name, "BOOK", 0]])
      end

      it "tokenizes mixed case name" do
        tokens = described_class.new("MyElement").tokenize
        expect(tokens).to eq([[:name, "MyElement", 0]])
      end
    end

    context "whitespace handling" do
      it "skips leading whitespace" do
        tokens = described_class.new("  book").tokenize
        expect(tokens).to eq([[:name, "book", 2]])
      end

      it "skips trailing whitespace" do
        tokens = described_class.new("book  ").tokenize
        expect(tokens).to eq([[:name, "book", 0]])
      end

      it "skips whitespace between tokens" do
        tokens = described_class.new("book   @id").tokenize
        expect(tokens).to eq([[:name, "book", 0], [:at, "@", 7],
                              [:name, "id", 8]])
      end

      it "handles tabs and newlines" do
        tokens = described_class.new("book\t\n@id").tokenize
        expect(tokens).to eq([[:name, "book", 0], [:at, "@", 6],
                              [:name, "id", 7]])
      end
    end

    context "complex expressions" do
      it "tokenizes simple path" do
        tokens = described_class.new("/root/child").tokenize
        expect(tokens).to eq([
                               [:slash, "/", 0],
                               [:name, "root", 1],
                               [:slash, "/", 5],
                               [:name, "child", 6],
                             ])
      end

      it "tokenizes descendant path" do
        tokens = described_class.new("//book").tokenize
        expect(tokens).to eq([
                               [:dslash, "//", 0],
                               [:name, "book", 2],
                             ])
      end

      it "tokenizes attribute predicate" do
        tokens = described_class.new("book[@id]").tokenize
        expect(tokens).to eq([
                               [:name, "book", 0],
                               [:lbracket, "[", 4],
                               [:at, "@", 5],
                               [:name, "id", 6],
                               [:rbracket, "]", 8],
                             ])
      end

      it "tokenizes comparison predicate" do
        tokens = described_class.new("book[@price < 10]").tokenize
        expect(tokens).to eq([
                               [:name, "book", 0],
                               [:lbracket, "[", 4],
                               [:at, "@", 5],
                               [:name, "price", 6],
                               [:lt, "<", 12],
                               [:number, "10", 14],
                               [:rbracket, "]", 16],
                             ])
      end

      it "tokenizes function call" do
        tokens = described_class.new("count(//item)").tokenize
        expect(tokens).to eq([
                               [:name, "count", 0],
                               [:lparen, "(", 5],
                               [:dslash, "//", 6],
                               [:name, "item", 8],
                               [:rparen, ")", 12],
                             ])
      end

      it "tokenizes union expression" do
        tokens = described_class.new("book | article").tokenize
        expect(tokens).to eq([
                               [:name, "book", 0],
                               [:pipe, "|", 5],
                               [:name, "article", 7],
                             ])
      end

      it "tokenizes arithmetic expression" do
        tokens = described_class.new("@a + @b").tokenize
        expect(tokens).to eq([
                               [:at, "@", 0],
                               [:name, "a", 1],
                               [:plus, "+", 3],
                               [:at, "@", 5],
                               [:name, "b", 6],
                             ])
      end

      it "tokenizes logical expression" do
        tokens = described_class.new("@a and @b or @c").tokenize
        expect(tokens).to eq([
                               [:at, "@", 0],
                               [:name, "a", 1],
                               [:and, "and", 3],
                               [:at, "@", 7],
                               [:name, "b", 8],
                               [:or, "or", 10],
                               [:at, "@", 13],
                               [:name, "c", 14],
                             ])
      end

      it "tokenizes namespaced name" do
        tokens = described_class.new("ns:element").tokenize
        expect(tokens).to eq([
                               [:name, "ns", 0],
                               [:colon, ":", 2],
                               [:name, "element", 3],
                             ])
      end

      it "tokenizes axis with node test" do
        tokens = described_class.new("child::book").tokenize
        expect(tokens).to eq([
                               [:axis, "child", 0],
                               [:dcolon, "::", 5],
                               [:name, "book", 7],
                             ])
      end
    end

    context "error handling" do
      it "raises error for unexpected exclamation mark" do
        expect { described_class.new("!").tokenize }
          .to raise_error(Moxml::XPath::SyntaxError, /Unexpected '!'/)
      end

      it "raises error for unexpected character" do
        expect { described_class.new("#").tokenize }
          .to raise_error(Moxml::XPath::SyntaxError, /Unexpected character/)
      end

      it "raises error for unterminated double-quoted string" do
        expect { described_class.new('"unterminated').tokenize }
          .to raise_error(Moxml::XPath::SyntaxError, /Unterminated string/)
      end

      it "raises error for unterminated single-quoted string" do
        expect { described_class.new("'unterminated").tokenize }
          .to raise_error(Moxml::XPath::SyntaxError, /Unterminated string/)
      end
    end

    context "edge cases" do
      it "tokenizes empty expression" do
        tokens = described_class.new("").tokenize
        expect(tokens).to eq([])
      end

      it "tokenizes only whitespace" do
        tokens = described_class.new("   ").tokenize
        expect(tokens).to eq([])
      end

      it "tokenizes wildcard" do
        tokens = described_class.new("*").tokenize
        expect(tokens).to eq([[:star, "*", 0]])
      end

      it "tokenizes parent shorthand" do
        tokens = described_class.new("..").tokenize
        expect(tokens).to eq([[:ddot, "..", 0]])
      end

      it "tokenizes current shorthand" do
        tokens = described_class.new(".").tokenize
        expect(tokens).to eq([[:dot, ".", 0]])
      end

      it "tokenizes variable reference" do
        tokens = described_class.new("$var").tokenize
        expect(tokens).to eq([
                               [:dollar, "$", 0],
                               [:name, "var", 1],
                             ])
      end

      it "preserves token positions correctly" do
        tokens = described_class.new("a + b").tokenize
        expect(tokens.map(&:last)).to eq([0, 2, 4])
      end
    end
  end
end
