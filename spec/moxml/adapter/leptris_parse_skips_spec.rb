# frozen_string_literal: true

require "spec_helper"

DUP_XML = %(<r><e id="1">text</e><e id="2" id="3"/></r>)
POS_XML = %(<r><e id="1">text</e></r>)

RSpec.describe "Moxml leptris parse bookkeeping opt-outs" do
  # leptris-ruby#352 (binding 1.9.273.1, engine 1.9.272 Door A):
  # SKIP_DUP_DETECTION admits duplicate attributes silently (first
  # wins, no recover diagnostic); SKIP_SOURCE_POSITIONS degrades
  # source columns (lines still resolve). Caller opt-in only.
  let(:ctx) { Moxml.new(:leptris) }
  let(:adapter) { ctx.config.adapter }

  before do
    skip "binding without the SKIP_ parse flags" unless
      Leptris::XML::ParseOptions.const_defined?(:SKIP_DUP_DETECTION)
  end

  it "drops the duplicate-attribute diagnostic when requested" do
    doc = ctx.parse(DUP_XML, skip_dup_detection: true)
    expect(adapter.parse_diagnostics(doc.native)).to eq([])
  end

  it "keeps the duplicate-attribute diagnostic by default" do
    doc = ctx.parse(DUP_XML)
    expect(adapter.parse_diagnostics(doc.native).map { |d| d[:kind] }).to include(:recover)
  end

  it "first attribute wins either way" do
    expect(ctx.parse(DUP_XML, skip_dup_detection: true).root.children[1][:id])
      .to eq(ctx.parse(DUP_XML).root.children[1][:id])
  end

  it "keeps lines but degrades columns for skipped positions" do
    full = ctx.parse(POS_XML).root.children[0].source_position
    skipped = ctx.parse(POS_XML, skip_source_positions: true)
      .root.children[0].source_position
    expect(skipped[:line]).to eq(full[:line])
    expect(skipped[:col_start]).to be < full[:col_start]
  end

  it "keeps the duplicate in the tree — queries still answer first-wins" do
    # The engine admits the duplicate silently: reads see the first
    # value, but the second attribute stays in the tree, so the
    # serialized form can carry it. Callers opting in trade the
    # well-formed-output guarantee for the bookkeeping speed.
    fast = ctx.parse(DUP_XML, skip_dup_detection: true)
    expect(fast.root.children[1][:id]).to eq("2")
    expect(fast.to_xml).to include('id="2" id="3"')
  end

  it "still raises on fatal errors with skips on" do
    expect { ctx.parse("<r><e></r>", skip_dup_detection: true) }
      .to raise_error(Moxml::ParseError)
  end
end
