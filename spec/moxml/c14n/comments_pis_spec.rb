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
    # TODO.c14n/09: Document-level PIs (outside the document element) are
    # not yet rendered correctly. The moxml PI parser mis-parses document-level
    # PIs, and the DataModel.from_document path drops them. Fixing requires
    # adapter-level work and is tracked separately.
    it "renders PIs outside the document element (KNOWN LIMITATION)" do
      skip "document-level PI rendering not yet implemented"
    end
  end

  describe "comments at document level" do
    it "renders document-level comments when with_comments: true (KNOWN LIMITATION)" do
      skip "document-level comment rendering not yet implemented"
    end
  end
end
