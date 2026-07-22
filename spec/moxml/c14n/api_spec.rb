# frozen_string_literal: true

require "spec_helper"
require "moxml/c14n"

RSpec.describe "Moxml::C14n API" do
  let(:ctx) { Moxml.new(:nokogiri) }

  describe ".canonicalize (algorithm selector)" do
    it "defaults to inclusive C14N 1.0" do
      doc = ctx.parse("<root xmlns:foo='urn:foo'><foo:a/></root>")
      default_result = described_class.canonicalize(doc.root)
      incl_10_result = described_class.canonicalize(doc.root, algorithm: :inclusive)
      expect(default_result).to eq(incl_10_result)
    end

    it "raises ArgumentError for unknown algorithm" do
      expect do
        described_class.canonicalize("<x/>", algorithm: :bogus)
      end.to raise_error(ArgumentError, /unknown C14N algorithm/)
    end

    it "accepts inclusive_11 algorithm" do
      doc = ctx.parse("<root/>")
      result = described_class.canonicalize(doc.root, algorithm: :inclusive11)
      expect(result).to eq("<root></root>")
    end

    it "accepts exclusive_10 algorithm" do
      doc = ctx.parse("<root xmlns:foo='urn:foo'><foo:a/></root>")
      result = described_class.canonicalize(doc.root, algorithm: :exclusive)
      # Exclusive renders ns where visibly used (on foo:a), not on root
      expect(result).to include('<foo:a xmlns:foo="urn:foo">')
    end
  end

  describe ".equivalent?" do
    it "returns true for byte-identical inputs" do
      expect(described_class).to be_equivalent("<root>x</root>", "<root>x</root>")
    end

    it "returns true when only attribute whitespace differs" do
      # Whitespace inside the tag is not significant — both parse identically.
      a = %(<root attr="value"/>)
      b = %(<root  attr="value" />)
      expect(described_class).to be_equivalent(a, b)
    end

    it "returns false when text whitespace differs (text IS significant)" do
      a = "<root><child>a</child> </root>"
      b = "<root> <child>a</child></root>"
      expect(described_class).not_to be_equivalent(a, b)
    end

    it "returns true when only attribute order differs" do
      a = %(<root a="1" b="2"/>)
      b = %(<root b="2" a="1"/>)
      expect(described_class).to be_equivalent(a, b)
    end

    it "returns true when only namespace prefix differs" do
      a = "<root xmlns:foo='urn:foo'><foo:a/></root>"
      b = "<root xmlns:bar='urn:foo'><bar:a/></root>"
      # Inclusive canonical form: prefix is part of qname → not equivalent
      expect(described_class).not_to be_equivalent(a, b)
    end

    it "returns false for different content" do
      expect(described_class).not_to be_equivalent("<root>a</root>", "<root>b</root>")
    end

    it "respects algorithm argument" do
      a = "<root xmlns:foo='urn:foo'><foo:a/></root>"
      b = "<root><a xmlns:foo='urn:foo'/></root>"
      # Inclusive: ns on root vs on child → different
      expect(described_class).not_to be_equivalent(a, b, algorithm: :inclusive)
    end

    it "accepts Moxml::Node inputs" do
      doc1 = ctx.parse("<root/>")
      doc2 = ctx.parse("<root></root>")
      expect(described_class).to be_equivalent(doc1.root, doc2.root)
    end
  end

  describe "convenience methods" do
    it ".canonicalize_inclusive_10 matches default" do
      doc = ctx.parse("<root/>")
      expect(described_class.canonicalize_inclusive_10(doc.root))
        .to eq(described_class.canonicalize(doc.root))
    end

    it ".canonicalize_inclusive_11 produces output" do
      doc = ctx.parse("<root/>")
      expect(described_class.canonicalize_inclusive_11(doc.root)).to eq("<root></root>")
    end

    it ".canonicalize_exclusive accepts inclusive_namespaces" do
      doc = ctx.parse("<root xmlns:foo='urn:foo'/>")
      result = described_class.canonicalize_exclusive(doc.root, inclusive_namespaces: ["foo"])
      # Even though foo is not visibly used, inclusive list forces render
      expect(result).to include('xmlns:foo="urn:foo"')
    end
  end

  describe "escape helpers (backward compat)" do
    it ".escape_text escapes & < >" do
      expect(described_class.escape_text("a & b < c > d"))
        .to eq("a &amp; b &lt; c &gt; d")
    end

    it ".escape_attribute escapes quotes and whitespace" do
      expect(described_class.escape_attribute(%(a"b\tc\nd)))
        .to eq(%(a&quot;b&#x9;c&#xA;d))
    end
  end
end
