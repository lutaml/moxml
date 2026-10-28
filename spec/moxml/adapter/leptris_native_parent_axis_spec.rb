# frozen_string_literal: true

require "spec_helper"

# The parent step answers the OWNER element natively on bindings
# serving the fixed engine (1.9.385: leptris#1869 parent-of-attribute
# names the owner; the cross-doc adopt keeps its attribute chain) —
# moxml#474: the reverse-axis gate used to route every parent-axis
# expression to the Ruby engine, so the fast consumers (standoc's
# svg id cleanup runs `.//*[@id] | ./@id/..` per styled svg) paid
# the interpreter. Other reverse axes keep the Ruby lane (their
# native results are reverse-ordered; document order is the
# model's contract).
RSpec.describe "leptris native parent-axis lane" do
  let(:ctx) { Moxml.new(:leptris) }
  let(:doc) do
    ctx.parse('<root><svg id="s"><use id="u"/></svg></root>')
  end
  let(:svg) { doc.xpath("//*[local-name()='svg']").first }

  it "routes parent-of-attribute expressions to the native lane" do
    native = svg.adapter.native_xpath(
      svg.native, "./@id/..", {}
    )
    expect(native).not_to be_nil
  end

  it "answers the owner element through the facade" do
    expect(svg.xpath("./@id/..").map(&:name)).to eq(["svg"])
    expect(svg.xpath("./@id/..").first).to equal(svg)
  end

  it "serves the two-arm union natively" do
    expect(
      svg.xpath(".//*[@id] | ./@id/..").map(&:name).sort,
    ).to eq(%w[svg use])
  end

  it "keeps non-parent reverse axes on the Ruby lane" do
    doc2 = ctx.parse('<r><e a="1" b="2" c="3"/></r>')
    e = doc2.xpath("//e").first
    expect(e.xpath("ancestor::*").map(&:name)).to eq(["r"])
    native = e.adapter.native_xpath(e.native, "ancestor::*", {})
    expect(native).to be_nil
  end
end
