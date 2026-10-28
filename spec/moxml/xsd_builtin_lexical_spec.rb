# frozen_string_literal: true

# Processing model §Validation (normative): pinned here.

require "spec_helper"

RSpec.describe Moxml::XSD do
  let(:ctx) { Moxml.new(:leptris) }

  def valid_lexical?(type, lexical)
    described_class.builtin_valid?(ctx, type, lexical)
  end

  describe ".builtin_valid?" do
    it "answers the facade-owned table identically without an engine" do
      expect(valid_lexical?("xs:integer", "3")).to be(true)
      expect(valid_lexical?("xs:integer", "x")).to be(false)
      expect do
        described_class.builtin_valid?(ctx, "xs:nope", "3")
      end.to raise_error(ArgumentError)
    end

    it "applies whiteSpace=collapse before token-family checks" do
      expect(valid_lexical?("xs:token", "a  b")).to be(true)
      expect(valid_lexical?("xs:ID", " id ")).to be(true)
      expect(valid_lexical?("xs:NMTOKEN", "\tx ")).to be(true)
      expect(valid_lexical?("xs:ID", "1d")).to be(false)
    end

    it "keeps unbounded integers unbounded" do
      big = "1" * 29
      expect(valid_lexical?("xs:integer", big)).to be(true)
      expect(valid_lexical?("xs:positiveInteger", big)).to be(true)
      expect(valid_lexical?("xs:nonNegativeInteger", big)).to be(true)
      expect(valid_lexical?("xs:negativeInteger", "-1#{'0' * 20}")).to be(true)
      expect(valid_lexical?("xs:nonPositiveInteger", "0")).to be(true)
      expect(valid_lexical?("xs:nonPositiveInteger", "-0")).to be(true)
    end

    it "stops bounded integers at their own bounds" do
      expect(valid_lexical?("xs:long", "9223372036854775807")).to be(true)
      expect(valid_lexical?("xs:long", "9223372036854775808")).to be(false)
      expect(valid_lexical?("xs:unsignedLong", "18446744073709551615")).to be(true)
      expect(valid_lexical?("xs:unsignedLong", "18446744073709551616")).to be(false)
      expect(valid_lexical?("xs:byte", "128")).to be(false)
      expect(valid_lexical?("xs:unsignedByte", "256")).to be(false)
    end

    it "admits the float spellings the datatype spec defines" do
      expect(valid_lexical?("xs:float", "+INF")).to be(true)
      expect(valid_lexical?("xs:double", "-INF")).to be(true)
      expect(valid_lexical?("xs:float", "NaN")).to be(true)
      expect(valid_lexical?("xs:float", "1.5E-3")).to be(true)
      expect(valid_lexical?("xs:decimal", "5.")).to be(true)
      expect(valid_lexical?("xs:decimal", ".5")).to be(true)
      expect(valid_lexical?("xs:decimal", "1e3")).to be(false)
    end

    it "checks date lexicals against the Gregorian rules" do
      expect(valid_lexical?("xs:date", "2024-02-29")).to be(true)
      expect(valid_lexical?("xs:date", "1999-02-29")).to be(false)
      expect(valid_lexical?("xs:date", "2024-04-31")).to be(false)
      expect(valid_lexical?("xs:date", "2024-13-01")).to be(false)
    end

    it "checks dateTime and time lexicals" do
      expect(valid_lexical?("xs:dateTime", "2024-02-29T23:59:59Z")).to be(true)
      expect(valid_lexical?("xs:dateTime", "1999-02-29T00:00:00")).to be(false)
      expect(valid_lexical?("xs:time", "23:59:59.999+05:30")).to be(true)
      expect(valid_lexical?("xs:time", "24:00:00")).to be(false)
      expect(valid_lexical?("xs:time", "25:20:00")).to be(false)
      expect(valid_lexical?("xs:time", "13:20:60")).to be(false)
    end

    it "checks the gregorian-day lexicals" do
      expect(valid_lexical?("xs:gYearMonth", "2024-02Z")).to be(true)
      expect(valid_lexical?("xs:gYearMonth", "2024-13")).to be(false)
      expect(valid_lexical?("xs:gMonthDay", "--02-29")).to be(true)
      expect(valid_lexical?("xs:gMonthDay", "--02-30")).to be(false)
      expect(valid_lexical?("xs:gDay", "---31")).to be(true)
      expect(valid_lexical?("xs:gDay", "---32")).to be(false)
    end

    it "enforces the duration component rules" do
      expect(valid_lexical?("xs:duration", "P1Y2M3DT4H5M6.5S")).to be(true)
      expect(valid_lexical?("xs:duration", "PT0S")).to be(true)
      expect(valid_lexical?("xs:duration", "-P1D")).to be(true)
      expect(valid_lexical?("xs:duration", "P")).to be(false)
      expect(valid_lexical?("xs:duration", "PT")).to be(false)
      expect(valid_lexical?("xs:duration", "P1Y2MT")).to be(false)
      expect(valid_lexical?("xs:duration", "P200.5Y")).to be(false)
    end

    it "restricts the duration subtypes to their components" do
      expect(valid_lexical?("xs:dayTimeDuration", "P1DT2H")).to be(true)
      expect(valid_lexical?("xs:dayTimeDuration", "P1Y")).to be(false)
      expect(valid_lexical?("xs:yearMonthDuration", "P1Y2M")).to be(true)
      expect(valid_lexical?("xs:yearMonthDuration", "P1D")).to be(false)
      expect(valid_lexical?("xs:yearMonthDuration", "P1YT1H")).to be(false)
    end

    it "checks binary lexical spaces" do
      expect(valid_lexical?("xs:base64Binary", "aGVsbG8=")).to be(true)
      expect(valid_lexical?("xs:base64Binary", "abcd")).to be(true)
      expect(valid_lexical?("xs:base64Binary", "abcde")).to be(false)
      expect(valid_lexical?("xs:base64Binary", "a b")).to be(false)
      expect(valid_lexical?("xs:hexBinary", "0A")).to be(true)
      expect(valid_lexical?("xs:hexBinary", "0AB")).to be(false)
    end

    it "rejects the reserved xmlns prefix in QName-family lexicals" do
      expect(valid_lexical?("xs:QName", "foo")).to be(true)
      expect(valid_lexical?("xs:QName", "ns:foo")).to be(true)
      expect(valid_lexical?("xs:QName", "xmlns:xsi")).to be(false)
      expect(valid_lexical?("xs:QName", ":foo")).to be(false)
      expect(valid_lexical?("xs:QName", "a:b:c")).to be(false)
      expect(valid_lexical?("xs:NOTATION", "foo")).to be(true)
    end

    it "counts list items, not characters" do
      expect(valid_lexical?("xs:IDREFS", "a b")).to be(true)
      expect(valid_lexical?("xs:IDREFS", "a")).to be(true)
      expect(valid_lexical?("xs:IDREFS", "")).to be(false)
      expect(valid_lexical?("xs:NMTOKENS", "a.b-c:d e")).to be(true)
      expect(valid_lexical?("xs:ENTITIES", "a 1")).to be(false)
    end

    it "keeps the open lexical spaces open" do
      expect(valid_lexical?("xs:string", "anything <>&")).to be(true)
      expect(valid_lexical?("xs:anyURI", "http://example.com/a b")).to be(true)
      expect(valid_lexical?("xs:boolean", "true")).to be(true)
      expect(valid_lexical?("xs:boolean", "TRUE")).to be(false)
      expect(valid_lexical?("xs:language", "en-US")).to be(true)
      expect(valid_lexical?("xs:language", "en_US")).to be(false)
      expect(valid_lexical?("xs:Name", "a:b")).to be(true)
      expect(valid_lexical?("xs:NCName", "a:b")).to be(false)
    end
  end
end
