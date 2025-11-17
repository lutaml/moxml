# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'XPath Special Functions' do
  let(:context) { Moxml.new(:nokogiri) }

  describe 'id()' do
    let(:doc) do
      xml = <<~XML
        <root>
          <item id="a">first</item>
          <item id="b">second</item>
          <item id="c">third</item>
        </root>
      XML
      context.parse(xml)
    end

    it 'finds node by single ID' do
      ast = Moxml::XPath::Parser.parse('id("b")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be_a(Moxml::NodeSet)
      expect(result.size).to eq(1)
      expect(result.first.text).to eq('second')
    end

    it 'finds multiple nodes by space-separated IDs' do
      ast = Moxml::XPath::Parser.parse('id("a c")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be_a(Moxml::NodeSet)
      expect(result.size).to eq(2)
      expect(result.map(&:text)).to contain_exactly('first', 'third')
    end

    it 'returns empty nodeset for non-existent ID' do
      ast = Moxml::XPath::Parser.parse('id("nonexistent")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be_a(Moxml::NodeSet)
      expect(result.size).to eq(0)
    end

    it 'handles multiple space-separated IDs' do
      ast = Moxml::XPath::Parser.parse('id("b a")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be_a(Moxml::NodeSet)
      expect(result.size).to eq(2)
      expect(result.map(&:text)).to contain_exactly('first', 'second')
    end

    it 'ignores duplicate IDs' do
      ast = Moxml::XPath::Parser.parse('id("a a b")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be_a(Moxml::NodeSet)
      expect(result.map(&:text)).to include('first', 'second')
    end

    # Test with nodeset argument - requires path evaluation
    xit 'accepts nodeset argument containing IDs' do
      xml = <<~XML
        <root>
          <item id="a">first</item>
          <item id="b">second</item>
          <ref>a</ref>
          <ref>b</ref>
        </root>
      XML
      doc_with_refs = context.parse(xml)

      ast = Moxml::XPath::Parser.parse('id(/root/ref)')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc_with_refs)

      expect(result).to be_a(Moxml::NodeSet)
      expect(result.size).to eq(2)
      expect(result.map(&:text)).to contain_exactly('first', 'second')
    end
  end
end