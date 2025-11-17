# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'XPath Position Functions' do
  let(:context) { Moxml.new(:nokogiri) }

  let(:doc) do
    xml = <<~XML
      <root>
        <item>first</item>
        <item>second</item>
        <item>third</item>
      </root>
    XML
    context.parse(xml)
  end

  describe 'position()' do
    it 'raises error when used outside predicate' do
      ast = Moxml::XPath::Parser.parse('position()')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)

      expect { proc.call(doc) }.to raise_error(/position\(\) can only be used in a predicate/)
    end

    # These tests require predicate support to be implemented
    # They are marked as pending until predicates are working
    xit 'returns current position in predicate' do
      ast = Moxml::XPath::Parser.parse('/root/item[position() = 2]')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result.size).to eq(1)
      expect(result.first.text).to eq('second')
    end

    xit 'works with position comparison' do
      ast = Moxml::XPath::Parser.parse('/root/item[position() > 1]')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result.size).to eq(2)
      expect(result.map(&:text)).to eq(['second', 'third'])
    end
  end

  describe 'last()' do
    it 'raises error when used outside predicate' do
      ast = Moxml::XPath::Parser.parse('last()')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)

      expect { proc.call(doc) }.to raise_error(/last\(\) can only be used in a predicate/)
    end

    # These tests require predicate support to be implemented
    # They are marked as pending until predicates are working
    xit 'returns size of context in predicate' do
      ast = Moxml::XPath::Parser.parse('/root/item[position() = last()]')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result.size).to eq(1)
      expect(result.first.text).to eq('third')
    end

    xit 'works with last() - 1' do
      ast = Moxml::XPath::Parser.parse('/root/item[position() = last() - 1]')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result.size).to eq(1)
      expect(result.first.text).to eq('second')
    end

    xit 'works with comparison to last()' do
      ast = Moxml::XPath::Parser.parse('/root/item[position() < last()]')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result.size).to eq(2)
      expect(result.map(&:text)).to eq(['first', 'second'])
    end
  end
end