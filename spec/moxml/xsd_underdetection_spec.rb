# frozen_string_literal: true

require "spec_helper"

# Processing model §Validation (normative): pinned here.
# #452: tier-1 engines can accept, inside their recognized scope,
# instances that violate strict wildcards or xsi:nil. The
# Ruby-side SchemaRules post-validation closes those gaps from the
# schema source; findings merge with the engine's (duplicates
# dropped), so every adapter answers invalid for the four
# corpus shapes.
RSpec.describe "Moxml::XSD tier-1 under-detections (#452)" do
  %i[nokogiri leptris].each do |adapter_name|
    describe "on #{adapter_name}" do
      let(:ctx) { Moxml.new(adapter_name) }

      before do
        skip "#{adapter_name} requires an XSD-capable engine" unless
          Moxml::XSD.supported?(ctx)
      end

      describe "strict xs:any with an undeclared element" do
        let(:schema) do
          ctx.xsd(<<~XSD)
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                targetNamespace="http://example.com/w"
                elementFormDefault="qualified">
              <xs:element name="container">
                <xs:complexType>
                  <xs:sequence>
                    <xs:any namespace="##targetNamespace"
                            processContents="strict" minOccurs="0"/>
                  </xs:sequence>
                </xs:complexType>
              </xs:element>
              <xs:element name="known" type="xs:string"/>
            </xs:schema>
          XSD
        end

        it "rejects the undeclared wildcard match" do
          doc = ctx.parse(
            '<container xmlns="http://example.com/w"><unknown>x</unknown></container>',
          )
          expect(schema.valid?(doc)).to be(false)
          expect(schema.validate(doc).map(&:message)).to include(
            /matches a strict wildcard but is not declared/,
          )
        end

        it "accepts the declared wildcard match" do
          doc = ctx.parse(
            '<container xmlns="http://example.com/w"><known>x</known></container>',
          )
          expect(schema.valid?(doc)).to be(true)
        end

        it "leaves lax wildcards to the engine" do
          lax = ctx.xsd(<<~XSD)
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                targetNamespace="http://example.com/w"
                elementFormDefault="qualified">
              <xs:element name="container">
                <xs:complexType>
                  <xs:sequence>
                    <xs:any namespace="##targetNamespace"
                            processContents="lax" minOccurs="0"/>
                  </xs:sequence>
                </xs:complexType>
              </xs:element>
            </xs:schema>
          XSD
          doc = ctx.parse(
            '<container xmlns="http://example.com/w"><unknown>x</unknown></container>',
          )
          expect(lax.valid?(doc)).to be(true)
        end
      end

      describe "strict xs:anyAttribute with an undeclared attribute" do
        let(:schema) do
          ctx.xsd(<<~XSD)
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                targetNamespace="http://example.com/aa"
                elementFormDefault="qualified">
              <xs:element name="settings">
                <xs:complexType>
                  <xs:complexContent>
                    <xs:restriction base="xs:anyType">
                      <xs:attribute name="lang"/>
                      <xs:anyAttribute namespace="##targetNamespace ##local"
                                       processContents="strict"/>
                    </xs:restriction>
                  </xs:complexContent>
                </xs:complexType>
              </xs:element>
            </xs:schema>
          XSD
        end

        it "rejects the undeclared wildcard match" do
          doc = ctx.parse(
            '<settings xmlns="http://example.com/aa" lang="en" bogus="1">v</settings>',
          )
          expect(schema.valid?(doc)).to be(false)
          expect(schema.validate(doc).map(&:message)).to include(
            /attribute bogus matches a strict wildcard but is not declared/,
          )
        end

        it "accepts the declared attribute" do
          # self-closing: the empty-content-type reading of the
          # restriction is the engine's answer, not this rule's
          doc = ctx.parse(
            '<settings xmlns="http://example.com/aa" lang="en"/>',
          )
          expect(schema.valid?(doc)).to be(true)
        end
      end

      describe "xsi:nil on a non-nillable element" do
        let(:schema) do
          ctx.xsd(<<~XSD)
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                elementFormDefault="qualified">
              <xs:element name="memo" type="xs:string" nillable="true"/>
              <xs:element name="strict" type="xs:string"/>
            </xs:schema>
          XSD
        end

        it "rejects xsi:nil on the non-nillable declaration" do
          doc = ctx.parse(
            '<strict xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:nil="true"/>',
          )
          expect(schema.valid?(doc)).to be(false)
          expect(schema.validate(doc).map(&:message)).to include(
            /is not nillable but carries xsi:nil/,
          )
        end

        it "accepts xsi:nil on the nillable declaration" do
          doc = ctx.parse(
            '<memo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:nil="true"/>',
          )
          expect(schema.valid?(doc)).to be(true)
        end

        it "accepts the element without xsi:nil" do
          doc = ctx.parse("<strict>text</strict>")
          expect(schema.valid?(doc)).to be(true)
        end
      end

      describe "wrong-namespace root" do
        let(:schema) do
          ctx.xsd(<<~XSD)
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                targetNamespace="http://example.com/q"
                elementFormDefault="qualified">
              <xs:element name="note" type="xs:string"/>
            </xs:schema>
          XSD
        end

        it "rejects the root in the wrong namespace" do
          doc = ctx.parse(
            '<note xmlns="http://example.com/other">hi</note>',
          )
          expect(schema.valid?(doc)).to be(false)
        end
      end
    end
  end
end
