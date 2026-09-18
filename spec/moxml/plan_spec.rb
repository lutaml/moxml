# frozen_string_literal: true

require "spec_helper"

# Moxml::Plan: shape-compiled materialization over the adapter's
# bulk row stream (leptris C snapshot) and the generic wrapper walk.
# Both paths must produce identical values.
RSpec.describe Moxml::Plan do
  PlanRow = Struct.new(:id, :kind, :fields) # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration
  PlanCell = Struct.new(:name, :unit, :value) # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration

  let(:xml) do
    <<~XML
      <?xml version="1.0"?>
      <catalog>
        <record id="r0" kind="k0"><field name="f0" unit="u0">v 0.0</field><field name="f1" unit="u1">v 0.1</field></record>
        <record id="r1" kind="k1"><field name="f0" unit="u0">v 1.0</field></record>
      </catalog>
    XML
  end
  let(:plan) do
    described_class.new do
      on("record") do |attrs, _text, fields|
        PlanRow.new(attrs["id"], attrs["kind"], fields)
      end
      on("field") do |attrs, text, _kids|
        PlanCell.new(attrs["name"], attrs["unit"], text)
      end
    end
  end

  shared_examples "plan materialization" do |adapter_name|
    let(:ctx) { Moxml.new(adapter_name) }

    it "builds the typed shape" do
      rows = plan.parse(xml, ctx)

      expect(rows.size).to eq(2)
      expect(rows[0].id).to eq("r0")
      expect(rows[0].kind).to eq("k0")
      expect(rows[0].fields.size).to eq(2)
      expect(rows[0].fields[0]).to eq(PlanCell.new("f0", "u0", "v 0.0"))
      expect(rows[0].fields[1]).to eq(PlanCell.new("f1", "u1", "v 0.1"))
      expect(rows[1].fields[0].value).to eq("v 1.0")
    end

    it "drops values of unmatched parents" do
      orphans = described_class.new do
        on("field") { |attrs, text, _| PlanCell.new(attrs["name"], attrs["unit"], text) }
      end.parse(xml, ctx)

      # fields match everywhere; no record handler keeps them
      expect(orphans.size).to eq(3)
    end

    it "returns top-level values for a matched root" do
      roots = described_class.new do
        on("catalog") { |_a, _t, kids| [:catalog, kids] }
        on("record") { |attrs, _t, fields| [attrs["id"], fields] }
        on("field") { |attrs, text, _| [attrs["name"], text] }
      end.parse(xml, ctx)

      expect(roots.size).to eq(1)
      expect(roots[0][0]).to eq(:catalog)
      expect(roots[0][1].size).to eq(2)
    end

    it "handles depth-3 nesting" do
      deep = described_class.new do
        on("catalog") { |_a, _t, records| records }
        on("record") { |attrs, _t, fields| [attrs["id"], fields] }
        on("field") { |attrs, text, _| [attrs["name"], text] }
      end.parse(xml, ctx)

      expect(deep.size).to eq(1)
      expect(deep[0]).to eq(
        [["r0", [["f0", "v 0.0"], ["f1", "v 0.1"]]],
         ["r1", [["f0", "v 1.0"]]]],
      )
    end

    it "is reusable across documents" do
      first = plan.parse(xml, ctx)
      second = plan.parse(xml, ctx)

      expect(first).to eq(second)
    end
  end

  describe "bulk path (leptris)" do
    it_behaves_like "plan materialization", :leptris
  end

  describe "generic path" do
    it_behaves_like "plan materialization", :nokogiri
  end

  it "requires a handler block" do
    expect { described_class.new.on("x") }
      .to raise_error(ArgumentError, /requires a block/)
  end
end
