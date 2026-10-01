# frozen_string_literal: true

require "spec_helper"

# The Moxml::XSLT contract: compile once, apply many. Only engines
# with an XSLT processor implement it (nokogiri/libxslt; leptris
# covering XSLT 1.0-3.0). leptris does not thread top-level params
# yet (leptris-ruby#360) — non-empty params raise Moxml::XsltError.
SHEET_COUNT = <<~XSL
  <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
    <xsl:template match="/"><out><xsl:value-of select="count(//i)"/></out></xsl:template>
  </xsl:stylesheet>
XSL

RSpec.describe "Moxml::XSLT" do
  let(:ctx) { Moxml.new(adapter_name) }
  let(:doc) { ctx.parse("<r><i>1</i><i>2</i></r>") }

  context "with the nokogiri adapter" do
    let(:adapter_name) { :nokogiri }

    it "compiles and applies to a document" do
      sheet = ctx.xslt(SHEET_COUNT)
      expect(sheet.apply_to(doc).root.name).to eq("out")
      expect(sheet.apply_to(doc).root.text).to eq("2")
    end

    it "returns engine-serialized output as a string" do
      sheet = ctx.xslt(SHEET_COUNT)
      expect(sheet.apply_to_string(doc)).to include("<out>2</out>")
    end

    it "threads top-level params" do
      sheet = ctx.xslt(<<~XSL)
        <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
          <xsl:param name="n" select="'0'"/>
          <xsl:template match="/"><out><xsl:value-of select="$n"/></out></xsl:template>
        </xsl:stylesheet>
      XSL
      expect(sheet.apply_to_string(doc, params: { "n" => "7" })).to include("7")
    end

    it "raises XsltError on a malformed stylesheet" do
      expect { ctx.xslt("<not-a-stylesheet/>") }
        .to raise_error(Moxml::XsltError, /compile failed/)
    end

    it "raises XsltError on a broken transform" do
      sheet = ctx.xslt(<<~XSL)
        <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
          <xsl:template match="/"><out><xsl:value-of select="$undefined"/></out></xsl:template>
        </xsl:stylesheet>
      XSL
      expect { sheet.apply_to(doc) }.to raise_error(Moxml::XsltError)
    end

    it "reports support" do
      expect(Moxml::XSLT.supported?(ctx)).to be(true)
    end
  end

  context "with the leptris adapter" do
    let(:adapter_name) { :leptris }

    it "compiles and applies to a document" do
      sheet = ctx.xslt(SHEET_COUNT)
      expect(sheet.apply_to(doc).root.name).to eq("out")
      expect(sheet.apply_to(doc).root.text).to eq("2")
    end

    it "preserves fragments through the string face" do
      sheet = ctx.xslt(<<~XSL)
        <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
          <xsl:template match="/">plain text result</xsl:template>
        </xsl:stylesheet>
      XSL
      expect(sheet.apply_to_string(doc)).to include("plain text result")
    end

    it "raises XsltError on non-empty params (leptris-ruby#360)" do
      sheet = ctx.xslt(SHEET_COUNT)
      expect { sheet.apply_to(doc, params: { "n" => "7" }) }
        .to raise_error(Moxml::XsltError, /params.*#360/)
    end

    it "reports support" do
      expect(Moxml::XSLT.supported?(ctx)).to be(true)
    end
  end

  context "with an adapter without an engine" do
    let(:ctx) { Moxml.new(:rexml) }

    it "raises NotImplementedError at compile" do
      expect { ctx.xslt(SHEET_COUNT) }
        .to raise_error(Moxml::NotImplementedError, /nokogiri, leptris/)
    end

    it "answers supported? false" do
      expect(Moxml::XSLT.supported?(ctx)).to be(false)
    end
  end
end
