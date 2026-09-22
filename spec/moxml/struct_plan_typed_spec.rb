# frozen_string_literal: true

require "spec_helper"

# Typed plan scalars (leptris plan ABI, #1269a consumer face):
# [slot, type] declarations cast in C — Integer/Float/TrueClass/
# FalseClass members with no Ruby String materialized; unparseable
# input degrades to the raw String. Skipped unless the binding's
# executor carries the typed face.
RSpec.describe "Moxml::StructPlan typed scalars" do
  let(:ctx) { Moxml.new(:leptris) }
  let(:xml) do
    %(<r><item price="19.99" qty="3" ok="yes">42</item>) +
      %(<item price="bad" qty="x" ok="0">7</item></r>)
  end
  let(:plan) do
    Moxml::StructPlan.new do
      element "item", TypedItem,
              attrs: { "price" => %i[price float], "qty" => %i[qty integer],
                       "ok" => %i[ok boolean] },
              text: %i[label integer]
    end
  end

  before do
    skip "leptris adapter unavailable" unless ctx.config.adapter.name.end_with?("Leptris")
    Moxml::Adapter::Leptris # load
    skip "binding lacks the typed executor" unless Moxml::Adapter::Leptris::NATIVE_PLAN_TYPED
  end

  it "casts typed slots and degrades unparseable input to String" do
    items = plan.parse(xml, ctx)
    expect(items[0].price).to eq(19.99)
    expect(items[0].qty).to eq(3)
    expect(items[0].ok).to be(true)
    expect(items[0].label).to eq(42)

    expect(items[1].price).to eq("bad")
    expect(items[1].qty).to eq("x")
    expect(items[1].ok).to be(false)
    expect(items[1].label).to eq(7)
  end
end
