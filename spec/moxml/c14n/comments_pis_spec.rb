# frozen_string_literal: true

require "spec_helper"
require "moxml/c14n"

# Edge cases for comment and processing-instruction handling per
# W3C C14N 1.0 §2.6, §2.7.
RSpec.describe "C14N comments and PIs" do
  let(:ctx) { Moxml.new(:nokogiri) }

  describe "comments inside elements" do
    it "omits comments by default" do
      doc = ctx.parse("<root>a<!-- c -->b</root>")
      expect(Moxml::C14n.canonicalize(doc.root)).to eq("<root>ab</root>")
    end

    it "includes comments when with_comments: true" do
      doc = ctx.parse("<root>a<!-- c -->b</root>")
      expect(Moxml::C14n.canonicalize(doc.root, with_comments: true))
        .to eq("<root>a<!-- c -->b</root>")
    end

    it "preserves comment content verbatim" do
      doc = ctx.parse("<root><!-- &amp; <stuff> --></root>")
      expect(Moxml::C14n.canonicalize(doc.root, with_comments: true))
        .to eq("<root><!-- &amp; <stuff> --></root>")
    end
  end

  describe "processing instructions" do
    it "always renders PIs (not affected by with_comments)" do
      doc = ctx.parse("<root><?pi data?>x</root>")
      expect(Moxml::C14n.canonicalize(doc.root))
        .to eq("<root><?pi data?>x</root>")
    end

    it "renders PI without data when data is empty" do
      doc = ctx.parse("<root><?pi?>x</root>")
      expect(Moxml::C14n.canonicalize(doc.root))
        .to eq("<root><?pi?>x</root>")
    end

    it "preserves PI target and data verbatim" do
      doc = ctx.parse(%(<root><?xml-stylesheet href="a.css" type="text/css"?>x</root>))
      expect(Moxml::C14n.canonicalize(doc.root))
        .to include(%(<?xml-stylesheet href="a.css" type="text/css"?>))
    end
  end

  describe "PIs at document level" do
    it "renders PIs outside the document element in document order" do
      doc = ctx.parse(%(<?pi before?><root><?pi inner?></root><?pi after?>))
      expect(Moxml::C14n.canonicalize(doc))
        .to eq(%(<?pi before?>\n<root><?pi inner?></root>\n<?pi after?>))
    end

    it "uses exactly one newline between document-level nodes" do
      doc = ctx.parse(%(<?pi a?><?pi b?><root/><?pi c?>))
      expect(Moxml::C14n.canonicalize(doc))
        .to eq(%(<?pi a?>\n<?pi b?>\n<root></root>\n<?pi c?>))
    end

    it "omits the XML declaration from the canonical form" do
      doc = ctx.parse(%(<?xml version="1.0" encoding="UTF-8"?><root/>))
      expect(Moxml::C14n.canonicalize(doc)).to eq("<root></root>")
    end
  end

  describe "comments at document level" do
    it "renders document-level comments when with_comments: true" do
      doc = ctx.parse(%(<!--lead--><root><!--inner--></root><!--trail-->))
      expect(Moxml::C14n.canonicalize(doc, with_comments: true))
        .to eq(%(<!--lead-->\n<root><!--inner--></root>\n<!--trail-->))
    end

    it "keeps exactly one newline between a document-level PI and comment" do
      doc = ctx.parse(%(<?pi x?><!--lead--><root/>))
      expect(Moxml::C14n.canonicalize(doc, with_comments: true))
        .to eq(%(<?pi x?>\n<!--lead-->\n<root></root>))
    end
  end
end
