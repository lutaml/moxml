# frozen_string_literal: true

require "spec_helper"

# Moxml::StructPlan: the fully compiled grammar — struct slots
# declared once, minted in C on leptris (1.9.201.1+) and via the
# plan fallback everywhere else. Results must be identical to
# Moxml::Plan.
SRecord = Struct.new(:id, :kind, :fields)
SField = Struct.new(:name, :unit, :value)

RSpec.describe Moxml::StructPlan do
  let(:xml) do
    '<catalog><record id="r0" kind="k0"><field name="f0" unit="u0">v 0.0</field><field name="f1" unit="u1">v 0.1</field></record><record id="r1" kind="k1"><field name="f0" unit="u0">v 1.0</field></record></catalog>'
  end
  let(:plan) do
    described_class.new do
      element "record", SRecord,
              attrs: { "id" => :id, "kind" => :kind }, children: :fields
      element "field", SField,
              attrs: { "name" => :name, "unit" => :unit }, text: :value
    end
  end
  let(:block_plan) do
    Moxml::Plan.new do
      on("record") { |attrs, _t, fields| SRecord.new(attrs["id"], attrs["kind"], fields) }
      on("field") { |attrs, text, _k| SField.new(attrs["name"], attrs["unit"], text) }
    end
  end

  ADAPTERS = %i[leptris nokogiri ox oga rexml libxml].freeze # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration

  def with_adapter(name)
    yield Moxml.new(name)
  rescue StandardError
    skip "#{name} unavailable"
  end

  ADAPTERS.each do |adapter_name|
    describe "on #{adapter_name}" do
      it "materializes the same structs as Moxml::Plan" do
        with_adapter(adapter_name) do |ctx|
          expect(plan.parse(xml, ctx))
            .to eq(block_plan.parse(xml, ctx))
        end
      end
    end
  end

  it "treats unmatched elements as barriers like Moxml::Plan" do
    barrier_xml = "<catalog><wrap><record id=\"r9\"/></wrap><record id=\"r8\"/></catalog>"
    with_adapter(:leptris) do |ctx|
      rows = plan.parse(barrier_xml, ctx)
      expect(rows.map(&:id)).to eq(%w[r9 r8])
    end
  end

  it "runs the C executor on leptris (not the fallback)" do
    skip "binding lacks the C face (lockstep without it, e.g. 1.9.199.0)" unless
      Moxml::Adapter::Leptris.const_defined?(:NATIVE_PLAN_STRUCTS) &&
        Moxml::Adapter::Leptris::NATIVE_PLAN_STRUCTS

    with_adapter(:leptris) do |ctx|
      doc = ctx.parse(xml)
      roots = Moxml::Adapter::Leptris.plan_structs(
        doc.native,
        "record" => [SRecord, { "id" => :id, "kind" => :kind }, nil, :fields],
        "field" => [SField, { "name" => :name, "unit" => :unit }, :value, nil],
      )
      expect(roots).to eq(plan.parse(xml, ctx))
    end
  end
end
