# frozen_string_literal: true

require "spec_helper"

# #362.2: Schema#validate returns one error shape on every
# adapter — Moxml::XSD::ValidationError(message:, line:, column:,
# path:) — so consumers present findings uniformly. Each adapter
# fills what its engine reports; missing data is nil, never a
# guessed placeholder.
RSpec.describe "Moxml::XSD::ValidationError contract (#362.2)" do
  let(:schema_text) do
    <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="r">
          <xs:complexType>
            <xs:sequence>
              <xs:element name="a"/>
              <xs:element name="b"/>
            </xs:sequence>
          </xs:complexType>
        </xs:element>
      </xs:schema>
    XSD
  end
  let(:bad_doc) { "<r><a/></r>" }

  %i[nokogiri leptris].each do |adapter_name|
    describe "on #{adapter_name}" do
      let(:ctx) { Moxml.new(adapter_name) }
      let(:schema) { ctx.xsd(schema_text) }
      let(:errors) { schema.validate(ctx.parse(bad_doc)) }

      it "returns the structured contract" do
        expect(errors).not_to be_empty
        expect(errors).to all(be_a(Moxml::XSD::ValidationError))
        expect(errors.first.message).not_to be_empty
      end

      it "to_s preserves plain-string flows" do
        expect(errors.map(&:to_s)).to all(be_a(String))
      end
    end
  end

  describe "adapter payloads" do
    it "nokogiri carries the line (libxml2 structured errors)" do
      ctx = Moxml.new(:nokogiri)
      errors = ctx.xsd(schema_text).validate(ctx.parse(bad_doc))
      expect(errors.first.line).to eq(1)
    end

    it "leptris reports message only (line/path ride leptris-ruby#419)" do
      ctx = Moxml.new(:leptris)
      errors = ctx.xsd(schema_text).validate(ctx.parse(bad_doc))
      expect(errors.first.line).to be_nil
      expect(errors.first.path).to be_nil
    end
  end

  describe "the ValidationError object" do
    it "compares fieldwise and formats with the line" do
      a = Moxml::XSD::ValidationError.new(message: "boom", line: 3)
      b = Moxml::XSD::ValidationError.new(message: "boom", line: 3)
      c = Moxml::XSD::ValidationError.new(message: "other", line: 3)
      expect(a).to eq(b)
      expect(a).not_to eq(c)
      expect(a.to_s).to eq("3: boom")
      expect(Moxml::XSD::ValidationError.new(message: "bare").to_s)
        .to eq("bare")
    end
  end
end
