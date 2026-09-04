# frozen_string_literal: true

require "nokogiri"
require "moxml/adapter/nokogiri"

RSpec.describe Moxml::Adapter::Nokogiri do
  around do |example|
    Moxml.with_config(:nokogiri, true, "UTF-8") do
      example.run
    end
  end

  it_behaves_like "xml adapter"

  describe "HTML parsing" do
    let(:ctx) { Moxml.new(:nokogiri) }

    it "synthesizes the html/body structure with lowercased names" do
      doc = ctx.parse_html(%(<DIV CLASS="x">t</DIV>))
      expect(doc.root.name).to eq("html")
      body = doc.root.children.find(&:element?)
      expect(body.name).to eq("body")
      expect(body.at_xpath(".//div")["class"]).to eq("x")
    end

    it "implies end tags and decodes HTML entities" do
      doc = ctx.parse_html(%(<ul><li>caf&eacute;</ul>))
      expect(doc.xpath("//li").map(&:text)).to eq(["caf\u00e9"])
    end
  end

  describe "recover-mode error channel" do
    it "exposes recoverable syntax errors as parse_errors" do
      doc = Moxml.new(:nokogiri).parse("<root><unclosed>", strict: false)
      expect(doc.parse_errors).not_to be_empty
      expect(doc.parse_errors).to all(be_a(String))
    end
  end
end
