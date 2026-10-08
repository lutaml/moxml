# frozen_string_literal: true

require "spec_helper"

# Moxml::XSD contract (leptris tier-1 faces): compile + validate
# with accumulated errors; unsupported adapters raise
# NotImplementedError at compile.
RSpec.describe Moxml::XSD do
  let(:ctx) { Moxml.new(:leptris) }
  let(:schema_text) do
    <<~XSD
      <?xml version="1.0"?>
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="note" type="t_note"/>
        <xs:complexType name="t_note">
          <xs:sequence>
            <xs:element name="to" type="xs:string"/>
          </xs:sequence>
        </xs:complexType>
      </xs:schema>
    XSD
  end

  it "reports supported? on the leptris adapter" do
    skip "leptris adapter unavailable" unless
      Moxml::Adapter::Leptris::XSD_SUPPORTED

    expect(described_class.supported?(ctx)).to be(true)
  end

  context "when the adapter ships a validator" do
    before do
      skip "leptris 1.9.321+ engine required" unless
        Moxml::Adapter::Leptris::XSD_SUPPORTED
    end

    it "compiles and validates a good document" do
      schema = ctx.xsd(schema_text)
      doc = ctx.parse("<note><to>You</to></note>")
      expect(schema.valid?(doc)).to be(true)
      expect(schema.validate(doc)).to eq([])
    end

    it "returns accumulated messages for an invalid document" do
      schema = ctx.xsd(schema_text)
      errors = schema.validate("<note><wrong/></note>")
      expect(errors).not_to be_empty
    end

    it "validates raw XML strings and nodes" do
      schema = ctx.xsd(schema_text)
      doc = ctx.parse("<note><to>x</to></note>")
      expect(schema.valid?(doc.root)).to be(true)
      expect(schema.valid?("<note><to>x</to></note>")).to be(true)
      expect(schema.valid?("<note><wrong/></note>")).to be(false)
    end

    it "derives XSD_SUPPORTED from the engine face gate" do
      # The capability flag must not outrun the engine faces: a
      # misreleased lockstep (NATIVE_PLAN_STRUCTS lesson) would arm
      # compile against missing functions.
      expect(Moxml::Adapter::Leptris::XSD_SUPPORTED)
        .to eq(Moxml::Adapter::Leptris::NATIVE_XSD)
    end
  end
end
