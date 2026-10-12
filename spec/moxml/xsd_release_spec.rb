# frozen_string_literal: true

require "spec_helper"

# #362.3: Schema#release — deterministic drop where the engine
# supports it, an explicit no-op-with-false where it cannot, and
# a documented contract for long-lived validation services.
RSpec.describe "Moxml::XSD::Schema#release (#362.3)" do
  let(:schema_text) do
    <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="a" type="xs:string"/>
      </xs:schema>
    XSD
  end

  describe "on leptris" do
    let(:ctx) { Moxml.new(:leptris) }

    context "with the release ride armed (binding >= 1.9.342.0)" do
      before do
        unless Moxml::Adapter::Leptris::XSD_RELEASE
          skip "binding #{Leptris::VERSION} predates Schema#release"
        end
      end

      it "drops the engine schema deterministically" do
        schema = ctx.xsd(schema_text)
        expect(schema.valid?(ctx.parse("<a/>"))).to be(true)
        expect(schema.release).to be(true)
        expect(schema.released?).to be(true)
      end

      it "raises on faces after release" do
        schema = ctx.xsd(schema_text)
        schema.release
        expect { schema.valid?(ctx.parse("<a/>")) }
          .to raise_error(Moxml::AdapterError, /released/)
        expect { schema.declarations }
          .to raise_error(Moxml::AdapterError, /released/)
      end

      it "frees without a double free at GC" do
        schema = ctx.xsd(schema_text)
        schema.release
        GC.start
        expect(schema.released?).to be(true)
      end
    end

    context "when the binding predates the ride" do
      before do
        if Moxml::Adapter::Leptris::XSD_RELEASE
          skip "binding #{Leptris::VERSION} carries Schema#release"
        end
      end

      it "answers false (GC-only) and keeps the schema usable" do
        schema = ctx.xsd(schema_text)
        expect(schema.release).to be(false)
        expect(schema).not_to be_released
        expect(schema.valid?(ctx.parse("<a/>"))).to be(true)
      end
    end
  end

  describe "on nokogiri" do
    it "answers false — libxml2 frees at GC, documented" do
      ctx = Moxml.new(:nokogiri)
      schema = ctx.xsd(schema_text)
      expect(schema.release).to be(false)
      expect(schema).not_to be_released
      expect(schema.valid?(ctx.parse("<a/>"))).to be(true)
    end
  end
end
