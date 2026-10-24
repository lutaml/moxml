# frozen_string_literal: true

require "spec_helper"

# Processing model §Validation (normative): pinned here.

# #460 item 2: a compiled schema reports the effective version its
# source declares — vc:minVersion="1.1" on the root scopes the
# document to 1.1 semantics; anything else reports 1.0. The
# detection is namespace-based (vc: is a convention, not a
# requirement) and reads the ROOT declaration; conditional
# (subtree-level) vc: evaluation is the engine's program.
RSpec.describe "Moxml::XSD::Schema#version (#460 item 2)" do
  %i[nokogiri leptris].each do |adapter_name|
    describe "on #{adapter_name}" do
      let(:ctx) { Moxml.new(adapter_name) }

      before do
        skip "#{adapter_name} requires an XSD-capable engine" unless
          Moxml::XSD.supported?(ctx)
      end

      it "reports 1.1 when the root declares vc:minVersion=1.1" do
        schema = ctx.xsd(<<~XSD)
          <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
              xmlns:vc="http://www.w3.org/2001/XMLSchema-versioning"
              vc:minVersion="1.1">
            <xs:element name="note" type="xs:string"/>
          </xs:schema>
        XSD
        expect(schema.version).to eq("1.1")
      end

      it "detects the versioning namespace, not the prefix" do
        schema = ctx.xsd(<<~XSD)
          <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
              xmlns:vcx="http://www.w3.org/2001/XMLSchema-versioning"
              vcx:minVersion="1.1">
            <xs:element name="note" type="xs:string"/>
          </xs:schema>
        XSD
        expect(schema.version).to eq("1.1")
      end

      it "reports 1.0 without a root version declaration" do
        schema = ctx.xsd(<<~XSD)
          <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
            <xs:element name="note" type="xs:string"/>
          </xs:schema>
        XSD
        expect(schema.version).to eq("1.0")
      end

      it "reports 1.0 for an explicit root vc:minVersion=1.0" do
        schema = ctx.xsd(<<~XSD)
          <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
              xmlns:vc="http://www.w3.org/2001/XMLSchema-versioning"
              vc:minVersion="1.0">
            <xs:element name="note" type="xs:string"/>
          </xs:schema>
        XSD
        expect(schema.version).to eq("1.0")
      end

      it "reports 1.0 when only a construct carries vc:minVersion" do
        schema = ctx.xsd(<<~XSD)
          <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
              xmlns:vc="http://www.w3.org/2001/XMLSchema-versioning">
            <xs:element name="note">
              <xs:complexType>
                <xs:sequence vc:minVersion="1.1">
                  <xs:element name="a"/>
                </xs:sequence>
              </xs:complexType>
            </xs:element>
          </xs:schema>
        XSD
        expect(schema.version).to eq("1.0")
      end
    end
  end
end
