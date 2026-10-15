# frozen_string_literal: true

require "moxml"

RSpec.describe "leptris adapter: declaration rides Document#children" do
  # leptris ruby#459 exposes the declaration as a document child; the
  # serializer emits the declaration in its preamble, so the child walk
  # must skip it — walking it duplicated the line (leptris#1732).
  let(:xml) do
    %(<?xml version="1.0" encoding="UTF-8"?>\n<documents/>)
  end

  it "round trips byte-identically, declaration emitted once" do
    doc = Moxml.parse(xml)
    out = doc.to_xml
    expect(out).to eq(xml)
    expect(out.scan("<?xml").size).to eq 1
  end

  it "survives repeated children reads" do
    doc = Moxml.parse(xml)
    2.times { doc.children }
    expect(doc.to_xml).to eq(xml)
  end
end
