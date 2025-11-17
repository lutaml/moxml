# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XPath String Functions" do
  let(:doc) do
    xml = <<~XML
      <root>
        <item>Hello World</item>
        <item>  Spaces  Around  </item>
        <item>UPPERCASE</item>
        <book id="1">Programming Ruby</book>
        <book id="2">Learning XML</book>
      </root>
    XML
    Moxml.new(:nokogiri).parse(xml)
  end

  describe "string()" do
    it "converts number to string" do
      ast = Moxml::XPath::Parser.parse("string(123)")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("123")
    end

    it "converts float to string" do
      ast = Moxml::XPath::Parser.parse("string(123.45)")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("123.45")
    end

    it "converts node to string" do
      ast = Moxml::XPath::Parser.parse("string(/root/item[1])")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("Hello World")
    end

    it "returns empty string for non-existent node" do
      ast = Moxml::XPath::Parser.parse("string(/root/nonexistent)")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("")
    end
  end

  describe "concat()" do
    it "concatenates two strings" do
      ast = Moxml::XPath::Parser.parse('concat("Hello", " World")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("Hello World")
    end

    it "concatenates multiple strings" do
      ast = Moxml::XPath::Parser.parse('concat("a", "b", "c", "d")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("abcd")
    end

    it "concatenates mixed literals and node values" do
      ast = Moxml::XPath::Parser.parse('concat("Book: ", /root/book[1])')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("Book: Programming Ruby")
    end
  end

  describe "starts-with()" do
    it "returns true for matching prefix" do
      ast = Moxml::XPath::Parser.parse('starts-with("Hello World", "Hello")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be true
    end

    it "returns false for non-matching prefix" do
      ast = Moxml::XPath::Parser.parse('starts-with("Hello World", "World")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be false
    end

    it "returns true for empty prefix" do
      ast = Moxml::XPath::Parser.parse('starts-with("Hello", "")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be true
    end

    it "works with node values" do
      ast = Moxml::XPath::Parser.parse('starts-with(/root/item[1], "Hello")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be true
    end
  end

  describe "contains()" do
    it "returns true when substring is present" do
      ast = Moxml::XPath::Parser.parse('contains("Hello World", "Wor")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be true
    end

    it "returns false when substring is not present" do
      ast = Moxml::XPath::Parser.parse('contains("Hello World", "xyz")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be false
    end

    it "is case-sensitive" do
      ast = Moxml::XPath::Parser.parse('contains("Hello World", "hello")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be false
    end

    it "works with node values" do
      ast = Moxml::XPath::Parser.parse('contains(/root/item[1], "World")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be true
    end
  end

  describe "substring-before()" do
    it "returns text before separator" do
      ast = Moxml::XPath::Parser.parse('substring-before("Hello:World", ":")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("Hello")
    end

    it "returns empty string when separator is not found" do
      ast = Moxml::XPath::Parser.parse('substring-before("Hello World", ":")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("")
    end

    it "works with multi-character separator" do
      ast = Moxml::XPath::Parser.parse('substring-before("Hello::World", "::")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("Hello")
    end
  end

  describe "substring-after()" do
    it "returns text after separator" do
      ast = Moxml::XPath::Parser.parse('substring-after("Hello:World", ":")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("World")
    end

    it "returns empty string when separator is not found" do
      ast = Moxml::XPath::Parser.parse('substring-after("Hello World", ":")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("")
    end

    it "works with multi-character separator" do
      ast = Moxml::XPath::Parser.parse('substring-after("Hello::World", "::")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("World")
    end
  end

  describe "substring()" do
    it "extracts substring with start and length" do
      ast = Moxml::XPath::Parser.parse('substring("Hello World", 1, 5)')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("Hello")
    end

    it "extracts substring with only start position" do
      ast = Moxml::XPath::Parser.parse('substring("Hello World", 7)')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("World")
    end

    it "handles start position in middle of string" do
      ast = Moxml::XPath::Parser.parse('substring("Hello World", 3, 3)')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("llo")
    end

    it "returns empty string when start is beyond string length" do
      ast = Moxml::XPath::Parser.parse('substring("Hello", 20, 5)')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("")
    end
  end

  describe "string-length()" do
    it "returns length of string literal" do
      ast = Moxml::XPath::Parser.parse('string-length("Hello")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(5.0)
    end

    it "returns zero for empty string" do
      ast = Moxml::XPath::Parser.parse('string-length("")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(0.0)
    end

    it "works with node values" do
      ast = Moxml::XPath::Parser.parse("string-length(/root/item[1])")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(11.0)
    end

    it "counts multi-byte characters correctly" do
      ast = Moxml::XPath::Parser.parse('string-length("Hello世界")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(7.0)
    end
  end

  describe "normalize-space()" do
    it "trims leading and trailing whitespace" do
      ast = Moxml::XPath::Parser.parse('normalize-space("  Hello  ")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("Hello")
    end

    it "collapses multiple spaces to single space" do
      ast = Moxml::XPath::Parser.parse('normalize-space("Hello   World")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("Hello World")
    end

    it "handles mixed whitespace characters" do
      ast = Moxml::XPath::Parser.parse('normalize-space("  Hello \t\n World  ")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("Hello World")
    end

    it "works with node values" do
      ast = Moxml::XPath::Parser.parse("normalize-space(/root/item[2])")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("Spaces Around")
    end

    it "returns empty string for whitespace-only input" do
      ast = Moxml::XPath::Parser.parse('normalize-space("   ")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("")
    end
  end

  describe "translate()" do
    it "translates single characters" do
      ast = Moxml::XPath::Parser.parse('translate("abc", "abc", "123")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("123")
    end

    it "removes characters when replacement is shorter" do
      ast = Moxml::XPath::Parser.parse('translate("abc", "abc", "12")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("12")
    end

    it "ignores extra replacement characters" do
      ast = Moxml::XPath::Parser.parse('translate("ab", "ab", "1234")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("12")
    end

    it "preserves untranslated characters" do
      ast = Moxml::XPath::Parser.parse('translate("hello", "el", "34")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("h344o")
    end

    it "works with case conversion" do
      ast = Moxml::XPath::Parser.parse('translate("hello", "helo", "HELO")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("HELLO")
    end
  end

  describe "function usage in predicates" do
    it "filters with contains()" do
      ast = Moxml::XPath::Parser.parse('//item[contains(., "Hello")]')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be_a(Moxml::NodeSet)
      expect(result.size).to eq(1)
      expect(result.first.text).to eq("Hello World")
    end

    it "filters with starts-with()" do
      ast = Moxml::XPath::Parser.parse('//book[starts-with(., "Programming")]')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be_a(Moxml::NodeSet)
      expect(result.size).to eq(1)
      expect(result.first.text).to eq("Programming Ruby")
    end

    it "filters with string-length()" do
      ast = Moxml::XPath::Parser.parse("//item[string-length(.) > 10]")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be_a(Moxml::NodeSet)
      expect(result.size).to eq(2)
    end
  end
end
