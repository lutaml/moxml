# frozen_string_literal: true

require "spec_helper"

# Loud degradation (processing model, "Errors and loud degradation"):
# a capability an engine cannot deliver must answer the contract or
# raise the named error — never a divergent answer. Probed across all
# available adapters; the capability lists mirror the adapters'
# actual engine backing.
RSpec.describe "loud capability contracts" do
  available = Moxml::Adapter::AVAILABLE_ADAPTERS
  xslt_capable = %i[nokogiri leptris] & available
  html_capable = %i[nokogiri leptris] & available

  let(:sheet) do
    %(<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">) \
      "<xsl:template match='/'><o/></xsl:template></xsl:stylesheet>"
  end

  (available - xslt_capable).each do |name|
    it "raises NotImplementedError for XSLT on #{name}" do
      ctx = Moxml.new(name)
      expect { ctx.xslt(sheet) }.to raise_error(Moxml::NotImplementedError)
    end
  end

  (available - html_capable).each do |name|
    it "raises NotImplementedError for to_xhtml on #{name}" do
      doc = Moxml.new(name).parse("<r><a/></r>")
      expect { doc.to_xhtml }.to raise_error(Moxml::NotImplementedError)
    end

    it "raises AdapterError for to_html on #{name}" do
      doc = Moxml.new(name).parse("<r><a/></r>")
      expect { doc.to_html }.to raise_error(Moxml::AdapterError)
    end
  end

  xslt_capable.each do |name|
    it "compiles a stylesheet on #{name}" do
      expect(Moxml.new(name).xslt(sheet)).to be_a(Moxml::XSLT::Stylesheet)
    end
  end
end
