# frozen_string_literal: true

require "spec_helper"
require "moxml/c14n"

# Edge cases for namespace rendering per W3C C14N 1.0 §2.3 / 1.1 §2.3.
# These cover the bugs that historically plague C14N implementations.
RSpec.describe "C14N namespace rendering" do
  let(:ctx) { Moxml.new(:nokogiri) }

  describe "default namespace" do
    it "renders xmlns= declaration when default ns is set" do
      doc = ctx.parse(%(<root xmlns="urn:foo"/>))
      result = Moxml::C14n.canonicalize(doc.root)
      expect(result).to eq('<root xmlns="urn:foo"></root>')
    end

    it "renders xmlns='' when transitioning to empty default" do
      doc = ctx.parse(%(<a xmlns="urn:foo"><b xmlns=""><c/></b></a>))
      result = Moxml::C14n.canonicalize(doc.root)
      # <b> has empty default; <a> has urn:foo → xmlns="" appears
      expect(result).to include('xmlns=""')
    end

    it "does not render xmlns when default ns is empty everywhere" do
      doc = ctx.parse(%(<root><child/></root>))
      result = Moxml::C14n.canonicalize(doc.root)
      expect(result).to eq("<root><child></child></root>")
    end
  end

  describe "prefix redeclaration" do
    it "renders both declarations when URI changes" do
      doc = ctx.parse(%(<a xmlns:x="urn:1"><b xmlns:x="urn:2"/></a>))
      result = Moxml::C14n.canonicalize(doc.root)
      expect(result.scan("xmlns:x=").length).to eq(2)
    end

    it "renders only once when URI is unchanged" do
      doc = ctx.parse(%(<a xmlns:x="urn:1"><b xmlns:x="urn:1"/></a>))
      result = Moxml::C14n.canonicalize(doc.root)
      expect(result.scan("xmlns:x=").length).to eq(1)
    end
  end

  describe "xml namespace" do
    it "does not render xmlns:xml declaration" do
      doc = ctx.parse(%(<root xmlns:xml="http://www.w3.org/XML/1998/namespace"/>))
      result = Moxml::C14n.canonicalize(doc.root)
      expect(result).not_to include("xmlns:xml=")
    end
  end

  describe "namespace sorting" do
    it "sorts xmlns declarations by prefix" do
      doc = ctx.parse(%(<root xmlns:z="urn:z" xmlns:a="urn:a"/>))
      result = Moxml::C14n.canonicalize(doc.root)
      # a should appear before z
      expect(result.index("xmlns:a=")).to be < result.index("xmlns:z=")
    end

    it "renders default namespace first" do
      doc = ctx.parse(%(<root xmlns="urn:default" xmlns:a="urn:a"/>))
      result = Moxml::C14n.canonicalize(doc.root)
      # Default (xmlns=) before prefixed
      expect(result.index("xmlns=")).to be < result.index("xmlns:a=")
    end
  end

  describe "deeply nested inheritance" do
    it "renders each prefix at the level it is first declared" do
      xml = <<~XML.strip
        <root xmlns:a="urn:a">
          <level1 xmlns:b="urn:b">
            <level2 xmlns:c="urn:c">
              <apex/>
            </level2>
          </level1>
        </root>
      XML
      doc = ctx.parse(xml)
      result = Moxml::C14n.canonicalize(doc.root)
      # Inclusive: all in-scope ns render on apex. But we're canonicalizing
      # the whole tree, so each ns renders at its declaration point.
      expect(result.scan("xmlns:").length).to eq(3)
    end
  end
end
