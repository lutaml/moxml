# frozen_string_literal: true

require "spec_helper"

# Cross-document adoption contract. leptris >= 1.9.311 absorbs the
# source document's pool into the destination (engine #1548) so
# attaches move by reference — wrapper identity survives; older
# bindings deep-copy at the splice (leptris-ruby#1528) and only the
# ADOPTION shape is pinned (the copy lands in the tree, correct
# names, doc-owned).
RSpec.describe "leptris cross-document adoption" do
  let(:ctx) { Moxml.new(:leptris) }
  let(:ad) { Moxml::Adapter::Leptris }

  it "add_child lands the adopted copy in the tree" do
    doc = ctx.parse("<r><a/></r>")
    other = ctx.parse("<other><new/></other>")
    child = other.root.children.first
    doc.root.add_child(child)
    last = doc.root.children.last
    expect(last.name).to eq("new")
    expect(last.text).to eq(child.text)
    expect(doc.root["unrelated"]).to be_nil
  end

  it "next= lands the adopted copy as the sibling" do
    doc = ctx.parse("<r><a/><b/></r>")
    other = ctx.parse("<other><x/></other>")
    child = other.root.children.first
    doc.at("//a").add_next_sibling(child)
    expect(doc.root.children.to_a[1].name).to eq("x")
    expect(doc.at("//r/x")).not_to be_nil
  end

  context "when the binding offers Document#absorb (>= 1.9.311)" do
    before do
      unless Moxml::Adapter::Leptris::NATIVE_DOC_ABSORB
        skip "binding #{Leptris::VERSION} has no absorb face"
      end
    end

    it "moves the child by reference — the wrapper addresses the attached node" do
      doc = ctx.parse("<r><a/></r>")
      other = ctx.parse("<other><new/></other>")
      child = other.root.children.first
      doc.root.add_child(child)
      expect(doc.root.children.last).to eq(child)
      expect(doc.root.to_xml).not_to include("<other")
      child["probe"] = "1"
      expect(doc.at("//r/new")["probe"]).to eq("1")
      expect(child.parent.name).to eq("r")
    end

    it "keeps the pre-311 adoption behavior for non-element kinds" do
      # Absorb is scoped to element moves: the binding's splice paths
      # drop absorbed-source nodes upstream (their absorbed_into?
      # check is not transitive), so binding-family children keep
      # the 1.9.304 adoption copy.
      doc = ctx.parse("<r/>")
      other = ctx.parse("<other/>")
      pi = other.create_processing_instruction("xml-stylesheet", 'href="s.xsl"')
      other.root.add_child(pi)
      doc.root.add_child(pi)
      expect(doc.root.to_xml).to include("<?xml-stylesheet")
    end

    it "keeps the tree alive after the source document is collected" do
      doc = ctx.parse("<r/>")
      child = nil
      3.times do
        other = ctx.parse("<other><deep><leaf v='1'>t</leaf></deep></other>")
        child = other.root.children.first
        doc.root.add_child(child)
        nil
        GC.start
      end
      expect(doc.at("//r/deep/leaf")["v"]).to eq("1")
      expect(doc.at("//r/deep/leaf").text).to eq("t")
      expect(child.name).to eq("deep")
    end

    it "keeps a living source readable after its pool is absorbed" do
      doc = ctx.parse("<r/>")
      other = ctx.parse("<other><x>1</x></other>")
      doc.root.add_child(other.root.children.first)
      expect(other.root.name).to eq("other")
      expect(other.at("//other")).not_to be_nil
    end

    it "moves elements whose pool was absorbed through an intermediate document" do
      # scratch → mid (first splice) → doc: the chase takes the pool
      # from mid; the raw engine add then moves by pool identity.
      doc = ctx.parse("<r/>")
      mid = ctx.parse("<mid/>")
      scratch = ctx.parse("<scratch><deep v='1'>t</deep></scratch>")
      mid.root.add_child(scratch.root.children.first)
      expect(mid.root.to_xml).to include("<deep")
      doc.root.add_child(mid.root.children.first)
      expect(doc.at("//r/deep")["v"]).to eq("1")
      expect(doc.root.to_xml).not_to include("<mid>")
      expect(mid.root.to_xml).not_to include("<deep")
    end
  end

  # moxml#335: the -1 fallback must not re-raise by node kind — the
  # engine's document resolution can mis-report pool ownership for
  # ANY child (the #1242 TLS-memo family), and only elements have a
  # cross-document identity worth a structural rebuild. The helper
  # is specced directly: the engine failure is CI-only, so forcing
  # the -1 locally is not reproducible.
  context "when the add_child -1 rebuild fallback fires" do
    it "rebuilds comments in the parent's document" do
      doc = ctx.parse("<r/>")
      other = ctx.parse("<other><!-- note --></other>")
      ad.rebuild_foreign_child(doc.root.native, other.root.children.first.native)
      expect(doc.root.to_xml).to include("<!-- note -->")
      expect(other.root.to_xml).to include("<!-- note -->")
    end

    it "rebuilds CDATA in the parent's document" do
      doc = ctx.parse("<r/>")
      other = ctx.parse("<other><![CDATA[x < y]]></other>")
      ad.rebuild_foreign_child(doc.root.native, other.root.children.first.native)
      expect(doc.root.to_xml).to include("<![CDATA[x < y]]>")
    end

    it "rebuilds processing instructions in the parent's document" do
      doc = ctx.parse("<r/>")
      other = ctx.parse("<other><?tgt data='1'?></other>")
      ad.rebuild_foreign_child(doc.root.native, other.root.children.first.native)
      expect(doc.root.to_xml).to include("<?tgt data='1'?>")
    end

    it "rebuilds text in the parent's document" do
      doc = ctx.parse("<r/>")
      other = ctx.parse("<other>t</other>")
      ad.rebuild_foreign_child(doc.root.native, other.root.children.first.native)
      expect(doc.root.to_xml).to include(">t<")
    end

    it "rebuilds elements structurally" do
      doc = ctx.parse("<r/>")
      other = ctx.parse("<other><e k='v'>t</e></other>")
      ad.rebuild_foreign_child(doc.root.native, other.root.children.first.native)
      expect(doc.at("//r/e")["k"]).to eq("v")
      expect(doc.at("//r/e").text).to eq("t")
    end
  end
end
