# frozen_string_literal: true

require "spec_helper"
require "moxml/signature"

RSpec.describe "Moxml C14N engine" do
  describe Moxml::C14n::Exclusive do
    let(:ctx) { Moxml.new(:nokogiri) }
    let(:canon) { described_class.new }

    it "renders a simple element without namespaces" do
      doc = ctx.parse("<root>hello</root>")
      expect(canon.canonicalize(doc.root)).to eq("<root>hello</root>")
    end

    it "preserves nested element structure" do
      doc = ctx.parse("<root><child>text</child></root>")
      expect(canon.canonicalize(doc.root)).to eq("<root><child>text</child></root>")
    end

    it "renders declared namespaces" do
      doc = ctx.parse(<<~XML.strip)
        <root xmlns:foo="http://example.com/foo"><foo:child>x</foo:child></root>
      XML
      result = canon.canonicalize(doc.root)
      # Exclusive C14N renders the namespace on the element where it's visibly
      # used (foo:child), not on ancestors that don't use it.
      expect(result).to include('<foo:child xmlns:foo="http://example.com/foo">')
      expect(result).to include("</foo:child>")
    end

    it "excludes ancestor-inherited namespaces when not visibly used (exclusive)" do
      doc = ctx.parse(<<~XML.strip)
        <outer xmlns:unused="http://example.com/unused"><inner>text</inner></outer>
      XML
      inner = doc.at_xpath("//inner")
      result = canon.canonicalize(inner)
      expect(result).to eq("<inner>text</inner>")
    end

    it "escapes special characters in text content" do
      doc = ctx.parse("<root>a&lt;b&gt;c&amp;d</root>")
      expect(canon.canonicalize(doc.root)).to eq("<root>a&lt;b&gt;c&amp;d</root>")
    end

    it "escapes special characters in attribute values" do
      doc = ctx.parse(%(<root attr="a&amp;b&quot;c"/>))
      expect(canon.canonicalize(doc.root))
        .to include(%(attr="a&amp;b&quot;c"))
    end

    it "sorts attributes by namespace URI then local name" do
      doc = ctx.parse(%(<root b="2" a="1" c="3"/>))
      result = canon.canonicalize(doc.root)
      expect(result).to include('a="1" b="2" c="3"')
    end

    it "omits comments by default" do
      doc = ctx.parse("<root>a<!-- comment -->b</root>")
      expect(canon.canonicalize(doc.root)).to eq("<root>ab</root>")
    end

    it "includes comments when with_comments is true" do
      doc = ctx.parse("<root>a<!-- comment -->b</root>")
      expect(canon.canonicalize(doc.root, with_comments: true))
        .to eq("<root>a<!-- comment -->b</root>")
    end
  end

  describe ".escape_text" do
    it "escapes &, <, >" do
      expect(Moxml::C14n.escape_text("a & b < c > d"))
        .to eq("a &amp; b &lt; c &gt; d")
    end

    it "escapes bare CR as &#xD;" do
      expect(Moxml::C14n.escape_text("a\rb"))
        .to eq("a&#xD;b")
    end
  end

  describe ".escape_attribute" do
    it "escapes quotes and tabs/newlines" do
      expect(Moxml::C14n.escape_attribute(%(a"b\tc\nd)))
        .to eq(%(a&quot;b&#x9;c&#xA;d))
    end
  end
end
