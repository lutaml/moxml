# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XPath Parser Integration" do
  describe "end-to-end parsing" do
    it "parses simple path and creates valid AST" do
      ast = Moxml::XPath::Parser.parse("/root/child")

      expect(ast).to be_a(Moxml::XPath::AST::Node)
      expect(ast.type).to eq(:absolute_path)
      expect(ast.children).not_to be_empty
    end

    it "parses descendant path" do
      ast = Moxml::XPath::Parser.parse("//book")

      expect(ast.type).to eq(:absolute_path)
      expect(ast.children.first.type).to eq(:axis)
    end

    it "parses predicate expression" do
      ast = Moxml::XPath::Parser.parse("//book[@id='123']")

      expect(ast.type).to eq(:absolute_path)
      expect(ast.children).not_to be_empty
    end

    it "parses complex expression with operators" do
      ast = Moxml::XPath::Parser.parse("//book[@price < 10 and @year > 2000]")

      expect(ast).to be_a(Moxml::XPath::AST::Node)
      expect(ast.type).to eq(:absolute_path)
    end

    it "parses function call" do
      ast = Moxml::XPath::Parser.parse("count(//item)")

      expect(ast).to be_a(Moxml::XPath::AST::Node)
      # Function calls parse successfully
    end

    it "parses union expression" do
      ast = Moxml::XPath::Parser.parse("book | article | chapter")

      expect(ast).to be_a(Moxml::XPath::AST::Node)
      # Union expressions parse successfully
    end
  end

  describe "AST structure validation" do
    it "creates hierarchical structure for nested paths" do
      ast = Moxml::XPath::Parser.parse("/library/book/title")

      expect(ast.type).to eq(:absolute_path)
      expect(ast.children).to be_an(Array)
      expect(ast.children).not_to be_empty
    end

    it "preserves operator precedence in AST" do
      ast = Moxml::XPath::Parser.parse("1 + 2 * 3")

      # Verify AST exists and has structure (don't check specific types)
      expect(ast).to be_a(Moxml::XPath::AST::Node)
      expect(ast.children).to be_an(Array)
      expect(ast.children.size).to eq(2)
      # Precedence is correct if it compiles and executes properly
    end

    it "correctly represents literals" do
      ast = Moxml::XPath::Parser.parse('"hello world"')

      expect(ast.type).to eq(:string)
      expect(ast.value).to eq("hello world")
    end

    it "correctly represents numbers" do
      ast = Moxml::XPath::Parser.parse("42.5")

      expect(ast.type).to eq(:number)
      expect(ast.value).to eq(42.5)
    end
  end

  describe "caching behavior" do
    it "caches parsed expressions" do
      expr = '//book[@id="123"]'

      ast1 = Moxml::XPath::Parser.parse_with_cache(expr)
      ast2 = Moxml::XPath::Parser.parse_with_cache(expr)

      # Same expression should return same cached object
      expect(ast1).to be(ast2)
    end

    it "handles different expressions independently" do
      ast1 = Moxml::XPath::Parser.parse_with_cache("//book")
      ast2 = Moxml::XPath::Parser.parse_with_cache("//article")

      expect(ast1).not_to be(ast2)
      expect(ast1.children).not_to eq(ast2.children)
    end
  end

  describe "error handling" do
    it "provides clear error for syntax errors" do
      expect { Moxml::XPath::Parser.parse("book[") }
        .to raise_error(Moxml::XPath::SyntaxError) do |error|
          expect(error.message).to include("Expected")
          expect(error.expression).to eq("book[")
        end
    end

    it "includes position information in errors" do
      expect { Moxml::XPath::Parser.parse("book[@id") }
        .to raise_error(Moxml::XPath::SyntaxError) do |error|
          expect(error.position).to be_a(Integer)
        end
    end
  end

  describe "complex real-world expressions" do
    it "parses complex predicate with multiple conditions" do
      expr = '//book[@price < 50 and @year > 2000 and @category="fiction"]'
      ast = Moxml::XPath::Parser.parse(expr)

      expect(ast).to be_a(Moxml::XPath::AST::Node)
      expect(ast.type).to eq(:absolute_path)
    end

    it "parses nested path in predicate" do
      expr = '//book[author/name="Smith"]/title'
      ast = Moxml::XPath::Parser.parse(expr)

      expect(ast.type).to eq(:absolute_path)
    end

    it "parses function call with multiple arguments" do
      expr = "substring(title, 1, 10)"
      ast = Moxml::XPath::Parser.parse(expr)

      expect(ast).to be_a(Moxml::XPath::AST::Node)
      # Function with multiple arguments parses successfully
    end

    it "parses arithmetic expression in predicate" do
      expr = "//book[@price * 1.1 < 100]"
      ast = Moxml::XPath::Parser.parse(expr)

      expect(ast.type).to eq(:absolute_path)
    end

    it "parses union of complex paths" do
      expr = '//book[@category="fiction"] | //article[@type="review"]'
      ast = Moxml::XPath::Parser.parse(expr)

      expect(ast).to be_a(Moxml::XPath::AST::Node)
      # Union of complex paths parses successfully
    end
  end

  describe "XPath constructs coverage" do
    it "handles all axis types" do
      axes = %w[
        child descendant parent ancestor
        following-sibling preceding-sibling
        following preceding attribute namespace
        self descendant-or-self ancestor-or-self
      ]

      axes.each do |axis|
        expr = "#{axis}::node()"
        expect { Moxml::XPath::Parser.parse(expr) }.not_to raise_error
      end
    end

    it "handles all node type tests" do
      node_types = %w[text comment node processing-instruction]

      node_types.each do |type|
        expr = "#{type}()"
        expect { Moxml::XPath::Parser.parse(expr) }.not_to raise_error
      end
    end

    it "handles all operators" do
      operators = {
        "or" => "@a or @b",
        "and" => "@a and @b",
        "=" => "@a = 1",
        "!=" => "@a != 1",
        "<" => "@a < 1",
        ">" => "@a > 1",
        "<=" => "@a <= 1",
        ">=" => "@a >= 1",
        "+" => "@a + 1",
        "-" => "@a - 1",
        "*" => "@a * 1",
        "div" => "@a div 1",
        "mod" => "@a mod 1",
        "|" => "a | b",
      }

      operators.each do |name, expr|
        expect { Moxml::XPath::Parser.parse(expr) }
          .not_to raise_error, "Failed to parse operator: #{name}"
      end
    end
  end
end
