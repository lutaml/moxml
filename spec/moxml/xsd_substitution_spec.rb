# frozen_string_literal: true

require "spec_helper"

# Processing model §Validation (normative): pinned here.
# #466 class 1: the engine's content-model matcher matches
# particles by exact name only, so a valid substitution-group
# member is rejected with "children do not match the content
# model". The Ruby-side dismissal drops such a finding only when
# the parent's content model is a pure sequence, the child
# sequence matches it position-for-position with every particle
# exactly-once, and a registered member realizes a position —
# any choice/all, cardinality violation, or unknown name keeps
# the engine's answer, so the dismissal can only remove false
# rejections, never create false acceptances.
RSpec.describe "Moxml::XSD substitution-group dismissal (#466)" do
  %i[nokogiri leptris].each do |adapter_name|
    describe "on #{adapter_name}" do
      let(:ctx) { Moxml.new(adapter_name) }

      before do
        skip "#{adapter_name} requires an XSD-capable engine" unless
          Moxml::XSD.supported?(ctx)
      end

      describe "member of a referenced head particle" do
        let(:schema) do
          ctx.xsd(<<~XSD)
            <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                xmlns:x="http://xsdtesting"
                targetNamespace="http://xsdtesting"
                elementFormDefault="qualified">
              <xsd:element name="doc">
                <xsd:complexType>
                  <xsd:sequence>
                    <xsd:element ref="x:elem1"/>
                  </xsd:sequence>
                </xsd:complexType>
              </xsd:element>
              <xsd:element name="elem1" abstract="false"/>
              <xsd:element name="elem2" substitutionGroup="x:elem1"/>
            </xsd:schema>
          XSD
        end

        it "accepts the member where the head is declared" do
          doc = ctx.parse(
            '<x:doc xmlns:x="http://xsdtesting"><x:elem2/></x:doc>',
          )
          expect(schema.valid?(doc)).to be(true)
        end

        it "accepts the head itself" do
          doc = ctx.parse(
            '<x:doc xmlns:x="http://xsdtesting"><x:elem1/></x:doc>',
          )
          expect(schema.valid?(doc)).to be(true)
        end

        it "rejects a stray non-member child" do
          doc = ctx.parse(
            '<x:doc xmlns:x="http://xsdtesting"><x:unknown/></x:doc>',
          )
          expect(schema.valid?(doc)).to be(false)
        end
      end

      describe "member inside a nested sequence" do
        let(:schema) do
          ctx.xsd(<<~XSD)
            <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                xmlns:x="http://xsdtesting"
                targetNamespace="http://xsdtesting"
                elementFormDefault="qualified">
              <xsd:element name="doc">
                <xsd:complexType>
                  <xsd:sequence>
                    <xsd:element ref="x:mid"/>
                  </xsd:sequence>
                </xsd:complexType>
              </xsd:element>
              <xsd:element name="mid">
                <xsd:complexType>
                  <xsd:sequence>
                    <xsd:element ref="x:elem1"/>
                  </xsd:sequence>
                </xsd:complexType>
              </xsd:element>
              <xsd:element name="elem1" abstract="false"/>
              <xsd:element name="elem2" substitutionGroup="x:elem1"/>
            </xsd:schema>
          XSD
        end

        it "accepts the member at the inner position" do
          doc = ctx.parse(
            '<x:doc xmlns:x="http://xsdtesting">' \
            "<x:mid><x:elem2/></x:mid></x:doc>",
          )
          expect(schema.valid?(doc)).to be(true)
        end
      end

      describe "models the dismissal refuses" do
        let(:schema) do
          ctx.xsd(<<~XSD)
            <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                xmlns:x="http://xsdtesting"
                targetNamespace="http://xsdtesting"
                elementFormDefault="qualified">
              <xsd:element name="doc">
                <xsd:complexType>
                  <xsd:choice>
                    <xsd:element ref="x:elem1"/>
                    <xsd:element name="other"/>
                  </xsd:choice>
                </xsd:complexType>
              </xsd:element>
              <xsd:element name="elem1" abstract="false"/>
              <xsd:element name="elem2" substitutionGroup="x:elem1"/>
            </xsd:schema>
          XSD
        end

        it "keeps the engine's answer for a two-child choice match" do
          # A choice takes one item; two children cannot be valid
          # even though both names resolve — the flattened particle
          # list is not a validity witness for non-sequences.
          doc = ctx.parse(
            '<x:doc xmlns:x="http://xsdtesting">' \
            "<x:elem2/><x:other/></x:doc>",
          )
          expect(schema.valid?(doc)).to be(false)
        end
      end

      describe "cardinality the dismissal refuses" do
        let(:schema) do
          ctx.xsd(<<~XSD)
            <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                xmlns:x="http://xsdtesting"
                targetNamespace="http://xsdtesting"
                elementFormDefault="qualified">
              <xsd:element name="doc">
                <xsd:complexType>
                  <xsd:sequence>
                    <xsd:element ref="x:elem1" minOccurs="2" maxOccurs="2"/>
                  </xsd:sequence>
                </xsd:complexType>
              </xsd:element>
              <xsd:element name="elem1" abstract="false"/>
              <xsd:element name="elem2" substitutionGroup="x:elem1"/>
            </xsd:schema>
          XSD
        end

        it "keeps the engine's answer below minOccurs" do
          doc = ctx.parse(
            '<x:doc xmlns:x="http://xsdtesting"><x:elem2/></x:doc>',
          )
          expect(schema.valid?(doc)).to be(false)
        end
      end
    end
  end
end
