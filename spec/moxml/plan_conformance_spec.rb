# frozen_string_literal: true

require "spec_helper"

# Moxml::Plan adapter-contract conformance (leptris follow-up to
# #249): every adapter must produce IDENTICAL plan results on the
# same document, whether its plan_rows is a bulk C stream (leptris,
# nokogiri, libxml) or a Ruby-native walk (ox, oga, rexml).
PlanRow = Struct.new(:id, :kind, :fields)
PlanCell = Struct.new(:name, :unit, :value)

RSpec.describe "Moxml::Plan adapter conformance" do
  # Single-line fixture: no inter-element whitespace text, so
  # engines that differ on insignificant text still agree.
  let(:xml) do
    '<catalog><record id="r0" kind="k0"><field name="f0" unit="u0">v 0.0</field><field name="f1" unit="u1">v 0.1</field></record><record id="r1" kind="k1"><field name="f0" unit="u0">v 1.0</field></record></catalog>'
  end

  let(:plan) do
    Moxml::Plan.new do
      on("record") do |attrs, _text, fields|
        PlanRow.new(attrs["id"], attrs["kind"], fields)
      end
      on("field") do |attrs, text, _kids|
        PlanCell.new(attrs["name"], attrs["unit"], text)
      end
    end
  end

  ADAPTERS = %i[leptris nokogiri ox oga rexml libxml].freeze # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration

  it "executes on every available adapter" do
    available = ADAPTERS.select do |a|
      ctx = Moxml.new(a)
      ctx.parse(xml)
      true
    rescue StandardError
      false
    end
    expect(available).not_to be_empty

    results = available.to_h { |a| [a, plan.parse(xml, Moxml.new(a))] }

    baseline = results[available.first]
    results.each do |adapter, rows|
      expect(rows).to eq(baseline), "adapter #{adapter} diverged"
    end

    expect(baseline.size).to eq(2)
    expect(baseline[0].fields.map(&:value)).to eq(["v 0.0", "v 0.1"])
  end

  it "skips no element and preserves order" do
    rows = plan.parse(xml, Moxml.new(:nokogiri))

    expect(rows.map(&:id)).to eq(%w[r0 r1])
  end

  it "handles depth-3 nesting identically" do
    deep = Moxml::Plan.new do
      on("catalog") { |_a, _t, records| records }
      on("record") { |attrs, _t, fields| [attrs["id"], fields] }
      on("field") { |attrs, text, _| [attrs["name"], text] }
    end

    ADAPTERS.each do |a|
      begin
        ctx = Moxml.new(a)
        ctx.parse(xml)
      rescue StandardError
        next
      end
      out = deep.parse(xml, ctx)
      expect(out[0]).to eq(
        [["r0", [["f0", "v 0.0"], ["f1", "v 0.1"]]],
         ["r1", [["f0", "v 1.0"]]]],
      )
    end
  end

  describe "plan-gate floors (moxml#344)" do
    let(:gate_ctx) { Moxml.new(:leptris) }

    it "arms both plan faces on engines carrying the #1585/#1586 fixes" do
      skip "testing engine predates the floor" unless
        Gem::Version.new(Leptris::VERSION) >= Gem::Version.new("1.9.320.0")

      expect(Moxml::Adapter::Leptris::NATIVE_PLAN_ROWS).to be(true)
      expect(Moxml::Adapter::Leptris::NATIVE_PLAN_STRUCTS).to be(true)
    end

    it "captures namespace-qualified wire attributes (leptris#1586)" do
      skip "plan faces degraded below 1.9.320 (moxml#344)" unless
        Moxml::Adapter::Leptris::NATIVE_PLAN_ROWS

      plan = Moxml::Plan.new do
        on("e") { |attrs| @captured = attrs }
      end
      plan.parse('<r xmlns:w="urn:w"><e w:name="Aptos"/></r>', gate_ctx)
      captured = plan.instance_variable_get(:@captured)
      expect(captured).to include("w:name" => "Aptos")
    end
  end
end
