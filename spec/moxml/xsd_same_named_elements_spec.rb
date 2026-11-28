# frozen_string_literal: true

require "spec_helper"

# moxml#594: a GLOBAL element `e` and a LOCAL element `e` coexist in
# one schema (XSD §3.3.3: local declarations shadow within their
# scope). The engine's automaton binds all same-named children to ONE
# declaration, rejecting documents whose local `e` content is valid
# against the LOCAL type; the occurrence-aware witness walk carries
# the per-particle proof and dismisses the false rejection.
RSpec.describe "same-named global/local element declarations" do
  let(:ctx) { Moxml.new(:leptris) }
  let(:schema) do
    ctx.xsd(<<~XSD)
      <?xml version="1.0"?>
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:complexType name="zing">
          <xs:sequence>
            <xs:element name="e" type="xs:integer"/>
            <xs:element name="f" type="xs:integer"/>
            <xs:any namespace="##local" processContents="lax"/>
          </xs:sequence>
        </xs:complexType>
        <xs:element name="doc" type="zing"/>
        <xs:element name="e" type="xs:positiveInteger"/>
      </xs:schema>
    XSD
  end

  before do
    skip "leptris adapter unavailable" unless
      Moxml::Adapter::Leptris::XSD_SUPPORTED
  end

  it "binds the local particle for the local position" do
    expect(schema.validate("<doc><e>-12</e><f>42</f></doc>")).to eq([])
  end

  it "keeps rejecting a local e that is not an integer" do
    expect(schema.validate("<doc><e>oops</e><f>42</f></doc>")).not_to be_empty
  end
end
