# frozen_string_literal: true

require "spec_helper"
require "moxml/c14n"

# Cross-engine agreement for the Moxml::XSLT contract. The corpus
# sticks to XSLT 1.0 shapes (the common denominator — nokogiri/
# libxslt speaks 1.0 only; leptris additionally covers 2.0/3.0 in its
# own suite). apply_to_string output is engine-serialized: the
# comparison strips a leading declaration when the engines disagree
# on emitting one.
SUPPORTED = %i[nokogiri leptris].select do |name|
  Moxml::Adapter::AVAILABLE_ADAPTERS.include?(name)
end.freeze

CORPUS = {
  "value-of with count" => [
    <<~XSL,
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
        <xsl:template match="/"><out><xsl:value-of select="count(//i)"/></out></xsl:template>
      </xsl:stylesheet>
    XSL
    "<r><i>1</i><i>2</i></r>",
    /<out>2<\/out>/,
  ],
  "for-each with sort" => [
    <<~XSL,
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
        <xsl:template match="/">
          <out><xsl:for-each select="//i"><xsl:sort select="." order="descending"/><v><xsl:value-of select="."/></v></xsl:for-each></out>
        </xsl:template>
      </xsl:stylesheet>
    XSL
    "<r><i>3</i><i>1</i><i>2</i></r>",
    /<v>3<\/v>\s*<v>2<\/v>\s*<v>1<\/v>/,
  ],
  "copy-of" => [
    <<~XSL,
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
        <xsl:template match="/"><out><xsl:copy-of select="//keep/*"/></out></xsl:template>
      </xsl:stylesheet>
    XSL
    %(<r><keep><a x="1">t</a></keep></r>),
    /<a x="1">t<\/a>/,
  ],
  "named template" => [
    <<~XSL,
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
        <xsl:template match="/"><out><xsl:call-template name="greet"/></out></xsl:template>
        <xsl:template name="greet">hi</xsl:template>
      </xsl:stylesheet>
    XSL
    "<r/>",
    /<out>hi<\/out>/,
  ],
  "attribute value template" => [
    <<~XSL,
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
        <xsl:template match="/"><out n="{count(//i)}"/></xsl:template>
      </xsl:stylesheet>
    XSL
    "<r><i/><i/></r>",
    /<out\s+n="2"\s*\/?>/,
  ],
  "namespaced output" => [
    <<~XSL,
      <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:o="urn:o" version="1.0">
        <xsl:template match="/"><o:out><xsl:value-of select="//t"/></o:out></xsl:template>
      </xsl:stylesheet>
    XSL
    "<r><t>v</t></r>",
    /<[^>]*:out[^>]*>v<\/[^>]*:out>/,
  ],
}.freeze

RSpec.describe "Moxml::XSLT cross-engine agreement" do
  SUPPORTED.each do |adapter_name|
    context "with the #{adapter_name} adapter" do
      let(:ctx) { Moxml.new(adapter_name) }

      def result_body(output)
        output.sub(/\A<\?xml[^>]*\?>\s*/, "")
      end

      CORPUS.each do |label, (sheet_xml, input, expected_re)|
        it "transforms #{label}" do
          sheet = ctx.xslt(sheet_xml)
          doc = ctx.parse(input)
          expect(result_body(sheet.apply_to_string(doc))).to match(expected_re)
          expect(sheet.apply_to(doc).to_xml).to match(expected_re)
        end
      end
    end
  end

  it "agrees across engines on the corpus" do
    return unless SUPPORTED.size == 2

    first, second = SUPPORTED.map { |name| Moxml.new(name) }
    CORPUS.each do |label, (sheet_xml, input, _)|
      a = first.xslt(sheet_xml).apply_to_string(first.parse(input))
      b = second.xslt(sheet_xml).apply_to_string(second.parse(input))
      expect(Moxml::C14n.equivalent?(a, b))
        .to(be(true), "#{label}: engines disagree\n a=#{a.inspect}\n b=#{b.inspect}")
    end
  end
end
