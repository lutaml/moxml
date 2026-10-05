# frozen_string_literal: true

require "spec_helper"

# leptris >= 1.9.304 adopts cross-document children BY COPY
# (leptris-ruby#1528 — the engine deep-copies at the splice so a
# scratch document can no longer dangle adopted nodes). The engine's
# status-returning splices cannot report the installed handle, so
# wrapper-level pointer identity for the appended node is not
# restorable yet (filed upstream): these pin the ADOPTION contract —
# the copy lands in the tree, correct names, doc-owned.
RSpec.describe "leptris cross-document adoption" do
  let(:ctx) { Moxml.new(:leptris) }

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
end
