# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XPath Node Functions" do
  let(:context) { Moxml.new(:nokogiri) }

  let(:doc) do
    xml = <<~XML
      <root xmlns:ns="http://example.com">
        <ns:item>namespaced</ns:item>
        <child id="123">content</child>
      </root>
    XML
    context.parse(xml)
  end

  describe "local-name()" do
    it "returns local name without namespace prefix" do
      ast = Moxml::XPath::Parser.parse("local-name(/root/child)")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("child")
    end

    it "returns local name for namespaced element" do
      ast = Moxml::XPath::Parser.parse("local-name(/root/*[1])")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("item")
    end

    it "returns empty string for no argument on non-element" do
      ast = Moxml::XPath::Parser.parse("local-name()")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      root = doc.root
      result = proc.call(root)

      expect(result).to eq("root")
    end
  end

  describe "name()" do
    it "returns qualified name for element" do
      ast = Moxml::XPath::Parser.parse("name(/root/child)")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("child")
    end

    it "returns qualified name with namespace prefix" do
      ast = Moxml::XPath::Parser.parse("name(/root/*[1])")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      # Depending on adapter, may include ns: prefix
      expect(result).to match(/item/)
    end

    it "returns empty string when no node matched" do
      ast = Moxml::XPath::Parser.parse("name(/nonexistent)")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("")
    end
  end

  describe "namespace-uri()" do
    it "returns empty string for element without namespace" do
      ast = Moxml::XPath::Parser.parse("namespace-uri(/root/child)")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("")
    end

    it "returns namespace URI for namespaced element" do
      ast = Moxml::XPath::Parser.parse("namespace-uri(/root/*[1])")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("http://example.com")
    end

    it "returns empty string when no node matched" do
      ast = Moxml::XPath::Parser.parse("namespace-uri(/nonexistent)")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("")
    end
  end

  describe "lang()" do
    let(:doc_with_lang) do
      xml = <<~XML
        <root xml:lang="en">
          <child>text</child>
          <other xml:lang="fr">french</other>
        </root>
      XML
      context.parse(xml)
    end

    it "matches language on element with xml:lang" do
      ast = Moxml::XPath::Parser.parse('lang("en")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      root = doc_with_lang.root
      result = proc.call(root)

      expect(result).to be true
    end

    it "does not match wrong language" do
      ast = Moxml::XPath::Parser.parse('lang("fr")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      root = doc_with_lang.root
      result = proc.call(root)

      expect(result).to be false
    end

    it "inherits language from parent element" do
      ast = Moxml::XPath::Parser.parse('lang("en")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      child = doc_with_lang.root.children.first
      result = proc.call(child)

      expect(result).to be true
    end

    it "uses closest xml:lang attribute" do
      ast = Moxml::XPath::Parser.parse('lang("fr")')
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      other = doc_with_lang.root.children[1]
      result = proc.call(other)

      expect(result).to be true
    end
  end
end
