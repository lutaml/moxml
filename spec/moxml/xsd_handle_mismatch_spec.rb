# frozen_string_literal: true

require "spec_helper"

# Issue #384: a schema handle compiled through one adapter must not
# dispatch through another — the misroute surfaced as a NoMethodError
# far from its cause when a silently-degraded context resolved to
# nokogiri while the handle came from the leptris API.
RSpec.describe "Moxml::XSD::Schema handle/adapter matching" do
  let(:leptris_ctx) { Moxml.new(:leptris) }
  let(:nokogiri_ctx) { Moxml.new(:nokogiri) }

  it "accepts a handle compiled through the same adapter" do
    schema = leptris_ctx.xsd("<xsd:schema xmlns:xsd='http://www.w3.org/2001/XMLSchema'/>")
    expect(schema).to be_a(Moxml::XSD::Schema)
  end

  it "raises a named mismatch at the wrap, not a distant NoMethodError" do
    handle = leptris_ctx.config.adapter.xsd_compile(
      "<xsd:schema xmlns:xsd='http://www.w3.org/2001/XMLSchema'/>",
    )

    expect do
      Moxml::XSD::Schema.new(handle, nokogiri_ctx)
    end.to raise_error(Moxml::AdapterError, /schema handle mismatch/)
  end

  it "keeps same-adapter validation working end to end" do
    schema = nokogiri_ctx.xsd(
      "<xsd:schema xmlns:xsd='http://www.w3.org/2001/XMLSchema'>" \
      "<xsd:element name='r'/></xsd:schema>",
    )
    expect(schema.valid?(nokogiri_ctx.parse("<r/>"))).to be(true)
  end
end
