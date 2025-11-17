# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XPath Boolean Functions" do
  let(:doc) do
    xml = "<root><item/></root>"
    Moxml.new(:nokogiri).parse(xml)
  end

  describe "boolean()" do
    it "converts non-empty string to true" do
      ast = Moxml::XPath::Parser.parse('boolean("text")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be true
    end

    it "converts empty string to false" do
      ast = Moxml::XPath::Parser.parse('boolean("")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be false
    end

    it "converts non-zero number to true" do
      ast = Moxml::XPath::Parser.parse("boolean(1)")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be true
    end

    it "converts zero to false" do
      ast = Moxml::XPath::Parser.parse("boolean(0)")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be false
    end

    it "converts NaN to false" do
      ast = Moxml::XPath::Parser.parse('boolean(number("not-a-number"))')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be false
    end
  end

  describe "not()" do
    it "negates true" do
      ast = Moxml::XPath::Parser.parse("not(true())")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be false
    end

    it "negates false" do
      ast = Moxml::XPath::Parser.parse("not(false())")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be true
    end

    it "negates non-empty string" do
      ast = Moxml::XPath::Parser.parse('not("text")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be false
    end

    it "negates empty string" do
      ast = Moxml::XPath::Parser.parse('not("")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be true
    end

    it "negates number" do
      ast = Moxml::XPath::Parser.parse("not(0)")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be true
    end
  end

  describe "true()" do
    it "returns true" do
      ast = Moxml::XPath::Parser.parse("true()")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be true
    end
  end

  describe "false()" do
    it "returns false" do
      ast = Moxml::XPath::Parser.parse("false()")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be false
    end
  end
end
