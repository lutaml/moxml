# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'XPath Numeric Functions' do
  let(:doc) do
    xml = <<~XML
      <root>
        <item price="10">A</item>
        <item price="20">B</item>
        <item price="30">C</item>
      </root>
    XML
    Moxml.new(:nokogiri).parse(xml)
  end

  describe 'number()' do
    it 'converts string to number' do
      ast = Moxml::XPath::Parser.parse('number("123.45")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(123.45)
    end

    it 'converts boolean true to number' do
      ast = Moxml::XPath::Parser.parse('number(true())')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(1.0)
    end

    it 'converts boolean false to number' do
      ast = Moxml::XPath::Parser.parse('number(false())')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(0.0)
    end
  end

  describe 'sum()' do
    it 'sums node values' do
      ast = Moxml::XPath::Parser.parse('sum(/root/item/@price)')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(60.0)
    end

    it 'returns 0 for empty nodeset' do
      ast = Moxml::XPath::Parser.parse('sum(/root/missing)')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(0.0)
    end
  end

  describe 'count()' do
    it 'counts nodes' do
      ast = Moxml::XPath::Parser.parse('count(/root/item)')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(3.0)
    end

    it 'returns 0 for empty nodeset' do
      ast = Moxml::XPath::Parser.parse('count(/root/missing)')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(0.0)
    end
  end

  describe 'floor()' do
    it 'rounds down positive number' do
      ast = Moxml::XPath::Parser.parse('floor(3.7)')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(3.0)
    end

    it 'rounds down negative number' do
      ast = Moxml::XPath::Parser.parse('floor(-3.2)')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(-4.0)
    end

    it 'leaves integer unchanged' do
      ast = Moxml::XPath::Parser.parse('floor(5)')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(5.0)
    end
  end

  describe 'ceiling()' do
    it 'rounds up positive number' do
      ast = Moxml::XPath::Parser.parse('ceiling(3.2)')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(4.0)
    end

    it 'rounds up negative number' do
      ast = Moxml::XPath::Parser.parse('ceiling(-3.7)')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(-3.0)
    end

    it 'leaves integer unchanged' do
      ast = Moxml::XPath::Parser.parse('ceiling(5)')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(5.0)
    end
  end

  describe 'round()' do
    it 'rounds to nearest (up)' do
      ast = Moxml::XPath::Parser.parse('round(3.5)')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(4.0)
    end

    it 'rounds to nearest (down)' do
      ast = Moxml::XPath::Parser.parse('round(3.4)')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(3.0)
    end

    it 'rounds negative numbers' do
      ast = Moxml::XPath::Parser.parse('round(-3.5)')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(-4.0)
    end

    it 'leaves integer unchanged' do
      ast = Moxml::XPath::Parser.parse('round(5)')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(5.0)
    end
  end
end