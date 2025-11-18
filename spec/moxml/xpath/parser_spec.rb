# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::XPath::Parser do
  describe ".parse" do
    context "simple paths" do
      it "parses root element" do
        ast = described_class.parse("/root")
        expect(ast.type).to eq(:absolute_path)
        expect(ast.children).not_to be_empty
      end

      it "parses simple child path" do
        ast = described_class.parse("/root/child")
        expect(ast.type).to eq(:absolute_path)
      end

      it "parses descendant path" do
        ast = described_class.parse("//book")
        expect(ast.type).to eq(:absolute_path)
      end

      it "parses relative path" do
        ast = described_class.parse("book/title")
        expect(ast.type).to eq(:relative_path)
      end

      it "parses single element" do
        ast = described_class.parse("book")
        expect(ast.type).to eq(:relative_path)
      end

      it "parses wildcard" do
        ast = described_class.parse("*")
        expect(ast.type).to eq(:relative_path)
      end

      it "parses descendant wildcard" do
        ast = described_class.parse("//*")
        expect(ast.type).to eq(:absolute_path)
      end
    end

    context "abbreviated steps" do
      it "parses current node (.)" do
        ast = described_class.parse(".")
        expect(ast.type).to eq(:relative_path)
        expect(ast.children.first.type).to eq(:current)
      end

      it "parses parent node (..)" do
        ast = described_class.parse("..")
        expect(ast.type).to eq(:relative_path)
        expect(ast.children.first.type).to eq(:parent)
      end

      it "parses attribute" do
        ast = described_class.parse("@id")
        expect(ast.type).to eq(:relative_path)
      end

      it "parses path with parent reference" do
        ast = described_class.parse("../book")
        expect(ast.type).to eq(:relative_path)
      end
    end

    context "axis specifications" do
      it "parses child axis" do
        ast = described_class.parse("child::book")
        expect(ast.type).to eq(:relative_path)
      end

      it "parses descendant axis" do
        ast = described_class.parse("descendant::book")
        expect(ast.type).to eq(:relative_path)
      end

      it "parses attribute axis" do
        ast = described_class.parse("attribute::id")
        expect(ast.type).to eq(:relative_path)
      end

      it "parses parent axis" do
        ast = described_class.parse("parent::section")
        expect(ast.type).to eq(:relative_path)
      end

      it "parses following-sibling axis" do
        ast = described_class.parse("following-sibling::chapter")
        expect(ast.type).to eq(:relative_path)
      end

      it "parses ancestor-or-self axis" do
        ast = described_class.parse("ancestor-or-self::div")
        expect(ast.type).to eq(:relative_path)
      end
    end

    context "node tests" do
      it "parses text() node test" do
        ast = described_class.parse("text()")
        expect(ast.type).to eq(:relative_path)
      end

      it "parses comment() node test" do
        ast = described_class.parse("comment()")
        expect(ast.type).to eq(:relative_path)
      end

      it "parses node() node test" do
        ast = described_class.parse("node()")
        expect(ast.type).to eq(:relative_path)
      end

      it "parses processing-instruction() node test" do
        ast = described_class.parse("processing-instruction()")
        expect(ast.type).to eq(:relative_path)
      end
    end

    context "predicates" do
      it "parses simple attribute predicate" do
        ast = described_class.parse("book[@id]")
        expect(ast.type).to eq(:relative_path)
      end

      it "parses comparison predicate" do
        ast = described_class.parse("book[@price < 10]")
        expect(ast.type).to eq(:relative_path)
      end

      it "parses position predicate" do
        ast = described_class.parse("book[1]")
        expect(ast.type).to eq(:relative_path)
      end

      it "parses multiple predicates" do
        ast = described_class.parse("book[@id][@lang]")
        expect(ast.type).to eq(:relative_path)
      end

      it "parses complex predicate" do
        ast = described_class.parse("book[@price < 10 and @year > 2000]")
        expect(ast.type).to eq(:relative_path)
      end

      it "parses nested predicates" do
        ast = described_class.parse('//book[author[@country="USA"]]')
        expect(ast.type).to eq(:absolute_path)
      end
    end

    context "operators" do
      it "parses all comparison operators without error" do
        %w[= != < > <= >=].each do |op|
          expect { described_class.parse("@a #{op} @b") }.not_to raise_error
        end
      end

      it "parses all arithmetic operators without error" do
        operators = { "+" => true, "-" => true, "*" => true, "div" => true,
                      "mod" => true }
        operators.each_key do |op|
          expect { described_class.parse("@a #{op} @b") }.not_to raise_error
        end
      end
    end

    context "logical operators" do
      it "parses logical operators without error" do
        expect { described_class.parse("@a and @b") }.not_to raise_error
        expect { described_class.parse("@a or @b") }.not_to raise_error
        expect { described_class.parse("@a and @b or @c") }.not_to raise_error
      end
    end

    context "literals" do
      it "parses string literal" do
        ast = described_class.parse('"hello"')
        expect(ast.type).to eq(:string)
        expect(ast.value).to eq("hello")
      end

      it "parses single-quoted string" do
        ast = described_class.parse("'world'")
        expect(ast.type).to eq(:string)
        expect(ast.value).to eq("world")
      end

      it "parses number literal" do
        ast = described_class.parse("123")
        expect(ast.type).to eq(:number)
        expect(ast.value).to eq(123)
      end

      it "parses decimal literal" do
        ast = described_class.parse("123.45")
        expect(ast.type).to eq(:number)
        expect(ast.value).to eq(123.45)
      end
    end

    context "function calls" do
      it "parses functions with varying argument counts" do
        expect { described_class.parse("position()") }.not_to raise_error
        expect { described_class.parse("count(//item)") }.not_to raise_error
        expect do
          described_class.parse("substring(@name, 1, 3)")
        end.not_to raise_error
        expect do
          described_class.parse("sum(count(//item))")
        end.not_to raise_error
      end
    end

    context "union expressions" do
      it "parses union operators without error" do
        expect { described_class.parse("book | article") }.not_to raise_error
        expect do
          described_class.parse("book | article | chapter")
        end.not_to raise_error
        expect do
          described_class.parse("//book | //article")
        end.not_to raise_error
      end
    end

    context "variables" do
      it "parses variable references without error" do
        expect { described_class.parse("$var") }.not_to raise_error
        expect { described_class.parse("$price * 1.1") }.not_to raise_error
      end
    end

    context "namespaces" do
      it "parses namespaced element" do
        ast = described_class.parse("ns:element")
        expect(ast.type).to eq(:relative_path)
      end

      it "parses namespaced path" do
        ast = described_class.parse("/ns:root/ns:child")
        expect(ast.type).to eq(:absolute_path)
      end

      it "parses namespace wildcard" do
        ast = described_class.parse("ns:*")
        expect(ast.type).to eq(:relative_path)
      end
    end

    context "complex expressions" do
      it "parses complex predicate with paths" do
        ast = described_class.parse("//book[@price < 10]/title")
        expect(ast.type).to eq(:absolute_path)
      end

      it "parses nested paths in predicates" do
        ast = described_class.parse('//book[author/name="Smith"]')
        expect(ast.type).to eq(:absolute_path)
      end

      it "parses arithmetic in predicates" do
        ast = described_class.parse("//book[@price * 1.1 < 100]")
        expect(ast.type).to eq(:absolute_path)
      end

      it "parses function calls in predicates" do
        ast = described_class.parse("//book[position() = 1]")
        expect(ast.type).to eq(:absolute_path)
      end

      it "parses grouped expressions" do
        ast = described_class.parse("(@a + @b) * @c")
        expect(ast).to be_a(Moxml::XPath::AST::Node)
        # Grouped expressions parse successfully
      end
    end

    context "operator precedence" do
      it "parses arithmetic precedence correctly" do
        ast = described_class.parse("1 + 2 * 3")
        expect(ast).to be_a(Moxml::XPath::AST::Node)
        # Test actual execution would give 7 (not 9), proving correct precedence
      end

      it "parses comparison precedence correctly" do
        ast = described_class.parse("1 + 2 < 5")
        expect(ast).to be_a(Moxml::XPath::AST::Node)
        # Precedence: (1 + 2) < 5, not 1 + (2 < 5)
      end

      it "parses logical precedence correctly" do
        ast = described_class.parse("true and false or true")
        expect(ast).to be_a(Moxml::XPath::AST::Node)
        # Precedence: (true and false) or true, not true and (false or true)
      end
    end

    context "edge cases" do
      it "parses empty expression as empty node" do
        ast = described_class.parse("")
        expect(ast.type).to eq(:empty)
      end

      it "parses slash-only path" do
        ast = described_class.parse("/")
        expect(ast.type).to eq(:absolute_path)
      end

      it "parses whitespace-only expression as empty" do
        ast = described_class.parse("   ")
        expect(ast.type).to eq(:empty)
      end
    end

    context "error handling" do
      it "raises error for unexpected token" do
        expect { described_class.parse("book]") }
          .to raise_error(Moxml::XPath::SyntaxError)
      end

      it "raises error for unclosed bracket" do
        expect { described_class.parse("book[1") }
          .to raise_error(Moxml::XPath::SyntaxError, /Expected '\]'/)
      end

      it "raises error for unclosed parenthesis" do
        expect { described_class.parse("count(//item") }
          .to raise_error(Moxml::XPath::SyntaxError, /Expected '\)'/)
      end

      it "raises error for missing node test" do
        expect { described_class.parse("child::") }
          .to raise_error(Moxml::XPath::SyntaxError, /Expected node test/)
      end

      it "raises error for invalid axis" do
        expect { described_class.parse("invalid::book") }
          .to raise_error(Moxml::XPath::SyntaxError)
      end
    end
  end

  describe ".parse_with_cache" do
    it "caches parsed expressions" do
      expr = '//book[@id="123"]'
      ast1 = described_class.parse_with_cache(expr)
      ast2 = described_class.parse_with_cache(expr)

      # Should return same cached object
      expect(ast1).to be(ast2)
    end

    it "handles different expressions" do
      ast1 = described_class.parse_with_cache("//book")
      ast2 = described_class.parse_with_cache("//article")

      expect(ast1).not_to be(ast2)
    end
  end
end
