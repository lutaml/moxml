# frozen_string_literal: true

require "spec_helper"

# Processing model §Validation (normative): pinned here.
# #464: an engine that cannot evaluate an XSD pattern-facet
# dialect construct (e.g. the \p{Is...} block escapes) rejects
# every occurrence of the facet — including values the facet
# accepts — false-positiving valid documents. The Ruby-side
# SchemaRules dismissal removes such engine findings only when the
# schema source's own pattern facets vouch for every same-named
# instance: one non-matching value keeps the engine's answer, so
# a dismissal can only remove false rejections, never create
# false acceptances. Constructs outside the translated dialect
# subset keep the engine's answer.
RSpec.describe "Moxml::XSD pattern-facet dismissal (#464)" do
  describe "bounded dialect translator" do
    let(:translator) { Moxml::XSD::SchemaRules::XsdRegex }

    it "translates block escapes and categories" do
      expect(translator.translate('\p{IsBasicLatin}+').source)
        .to eq("\\A(?:\\p{InBasicLatin}+)\\z")
      expect(translator.translate('\P{IsLatin-1Supplement}').source)
        .to eq("\\A(?:\\P{InLatin-1Supplement})\\z")
      expect(translator.translate('\p{IsGreek}').source)
        .to eq("\\A(?:\\p{InGreekandCoptic})\\z")
      expect(translator.translate('\p{L}').source)
        .to eq("\\A(?:\\p{L})\\z")
    end

    it "refuses constructs outside the translated subset" do
      expect(translator.translate('\i\c*')).to be_nil
      expect(translator.translate('[\p{IsBasicLatin}-[abc]]+'))
        .to be_nil
      expect(translator.translate('\p{IsNoSuchBlock}')).to be_nil
    end
  end

  %i[nokogiri leptris].each do |adapter_name|
    describe "on #{adapter_name}" do
      let(:ctx) { Moxml.new(adapter_name) }

      before do
        skip "#{adapter_name} requires an XSD-capable engine" unless
          Moxml::XSD.supported?(ctx)
      end

      describe "block-escape pattern on an element" do
        let(:schema) do
          ctx.xsd(<<~'XSD')
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
              <xs:element name="doc">
                <xs:complexType>
                  <xs:sequence>
                    <xs:element name="elem" type="regex"
                                minOccurs="1" maxOccurs="unbounded"/>
                  </xs:sequence>
                </xs:complexType>
              </xs:element>
              <xs:simpleType name="regex">
                <xs:restriction base="xs:string">
                  <xs:pattern value="\p{IsBasicLatin}+"/>
                </xs:restriction>
              </xs:simpleType>
            </xs:schema>
          XSD
        end

        it "accepts the value the facet accepts" do
          doc = ctx.parse(
            "<doc><elem>&#x9;&#xA;&#xD;&#x20;&#x7F;</elem></doc>",
          )
          expect(schema.valid?(doc)).to be(true)
        end

        it "rejects the value the facet rejects" do
          doc = ctx.parse(
            "<doc><elem>abc</elem><elem>ab&#233;c</elem></doc>",
          )
          expect(schema.valid?(doc)).to be(false)
        end
      end

      describe "negated block escape" do
        let(:schema) do
          ctx.xsd(<<~'XSD')
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
              <xs:element name="doc">
                <xs:complexType>
                  <xs:sequence>
                    <xs:element name="elem" type="nonbasic"
                                minOccurs="1"/>
                  </xs:sequence>
                </xs:complexType>
              </xs:element>
              <xs:simpleType name="nonbasic">
                <xs:restriction base="xs:string">
                  <xs:pattern value="\P{IsBasicLatin}"/>
                </xs:restriction>
              </xs:simpleType>
            </xs:schema>
          XSD
        end

        it "accepts a value outside the negated block" do
          doc = ctx.parse("<doc><elem>&#233;</elem></doc>")
          expect(schema.valid?(doc)).to be(true)
        end
      end

      describe "block-escape pattern on an attribute" do
        let(:schema) do
          ctx.xsd(<<~'XSD')
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
              <xs:element name="doc">
                <xs:complexType>
                  <xs:sequence>
                    <xs:element name="elem" minOccurs="1"
                                maxOccurs="unbounded">
                      <xs:complexType>
                        <xs:simpleContent>
                          <xs:extension base="xs:string">
                            <xs:attribute name="code">
                              <xs:simpleType>
                                <xs:restriction base="xs:string">
                                  <xs:pattern
                                      value="\p{IsBasicLatin}{2}"/>
                                </xs:restriction>
                              </xs:simpleType>
                            </xs:attribute>
                          </xs:extension>
                        </xs:simpleContent>
                      </xs:complexType>
                    </xs:element>
                  </xs:sequence>
                </xs:complexType>
              </xs:element>
            </xs:schema>
          XSD
        end

        it "accepts when every instance matches the facet" do
          doc = ctx.parse(
            '<doc><elem code="ab">x</elem><elem code="z9">y</elem></doc>',
          )
          expect(schema.valid?(doc)).to be(true)
        end

        it "rejects when one instance mismatches" do
          doc = ctx.parse(
            '<doc><elem code="ab">x</elem><elem code="1">y</elem></doc>',
          )
          expect(schema.valid?(doc)).to be(false)
        end
      end

      describe "class subtraction rides the engine unchanged" do
        let(:schema) do
          ctx.xsd(<<~'XSD')
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
              <xs:element name="doc">
                <xs:complexType>
                  <xs:sequence>
                    <xs:element name="elem" type="latinish"
                                minOccurs="1"/>
                  </xs:sequence>
                </xs:complexType>
              </xs:element>
              <xs:simpleType name="latinish">
                <xs:restriction base="xs:string">
                  <xs:pattern value="[\p{IsBasicLatin}-[abc]]+"/>
                </xs:restriction>
              </xs:simpleType>
            </xs:schema>
          XSD
        end

        it "keeps the engine's answer" do
          # The translation refuses subtraction, so the dismissal
          # never fires: both engines answer per their own
          # dialect coverage, unmodified by the facade.
          doc = ctx.parse("<doc><elem>xyz</elem></doc>")
          expect(schema.valid?(doc)).to be(true)
        end
      end
    end
  end
end
