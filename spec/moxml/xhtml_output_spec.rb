# frozen_string_literal: true

# Processing model §Serialization (normative): pinned here.

require "spec_helper"

# Issue #390: XHTML-shaped serialization — void elements self-closed
# (<br/>), non-void elements paired, raw text escaped, no XML
# declaration. Composes with the #354 indent knobs. Nokogiri's
# FORMAT | AS_XHTML | NO_DECLARATION save flag is the byte
# reference; canon's fixture_ready display lane rides the face.
RSpec.describe "XHTML output mode" do
  let(:doc) do
    Moxml.new(ENV.fetch("XHTML_ADAPTER", :leptris)).parse_html(
      '<!DOCTYPE html><html><body><p>a<br>b</p><img src="x.png">' \
      "<hr></body></html>",
    )
  end

  describe "Document#to_xhtml" do
    it "self-closes void elements with the XHTML slash" do
      out = doc.to_xhtml
      expect(out).not_to include("<br>")
      expect(out).to include("<br/>")
      expect(out).to include('<img src="x.png"/>')
      expect(out).to include("<hr/>")
    end

    it "pairs non-void elements" do
      out = doc.to_xhtml
      expect(out).to include("<p>a<br/>b</p>")
      expect(out).not_to include("<p/>")
    end

    it "omits the XML declaration" do
      expect(doc.to_xhtml).not_to start_with("<?xml")
    end

    it "keeps the doctype as document content" do
      expect(doc.to_xhtml).to include("<!DOCTYPE html>")
    end

    it "composes with the indent knobs" do
      out = doc.to_xhtml(indent: 2)
      expect(out).to include("\n  <body>")
      expect(out).to include("\n    <p>a<br/>b</p>")
    end

    it "escapes raw text per the XML method" do
      doc = Moxml.new(ENV.fetch("XHTML_ADAPTER", :leptris)).parse_html(
        "<!DOCTYPE html><html><body><script>if (a < b) { x(); }</script>" \
        "</body></html>",
      )
      out = doc.to_xhtml
      expect(out).not_to include("a < b")
      expect(out).to include("&lt;") if out.include?("script")
    end
  end

  describe "Document#to_html(xhtml: true)" do
    it "selects the same shape" do
      expect(doc.to_html(xhtml: true)).to eq(doc.to_xhtml)
    end

    it "still serves the HTML shape without the flag" do
      expect(doc.to_html).to include("<br>")
      expect(doc.to_html).not_to include("<br/>")
    end
  end

  describe "adapter coverage" do
    it "serves the nokogiri lane (the byte reference)" do
      doc = Moxml.new(:nokogiri).parse_html(
        "<!DOCTYPE html><html><body><p>a<br>b</p></body></html>",
      )
      out = doc.to_xhtml
      expect(out).to include("<br/>")
      expect(out).to include("<p>a<br/>b</p>")
    end
  end
end
