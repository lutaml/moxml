# frozen_string_literal: true

# Processing model §Document order and traversal (normative): pinned here.

RSpec.describe "Adapter Examples" do
  let(:xml) { "<root><child>text</child></root>" }

  describe "Document children listing" do
    it "never lists the XML declaration as a child" do
      Moxml::Adapter::AVAILABLE_ADAPTERS.each do |adapter|
        doc = Moxml.new(adapter)
          .parse(%(<?xml version="1.0"?><r/>))
        expect(doc.children.map(&:node_type)).to eq([:element]),
                                                 "#{adapter}: declaration leaked " \
                                                 "into children (model: state, not a node)"
        expect(doc.has_xml_declaration).to be(true),
                                           "#{adapter}: declaration state lost"
      end
    end

    it "lists the doctype per the Nokogiri contract" do
      Moxml::Adapter::AVAILABLE_ADAPTERS.each do |adapter|
        doc = Moxml.new(adapter).parse(%(<!DOCTYPE r><r/>))
        expect(doc.children.map(&:node_type)).to eq(%i[doctype element]),
                                                 "#{adapter}: doctype listing"
      end
    end
  end

  describe "Serialization consistency" do
    it "produces equivalent XML across adapters",
       skip: "No easy way to exclude the declaration from Nokogiri documents" do
      docs = Moxml::Adapter::AVAILABLE_ADAPTERS.map do |adapter|
        Moxml.new(adapter).parse(xml, fragment: true)
      end

      xmls = docs.map { |doc| normalize_xml(doc.to_xml) }
      expect(xmls.uniq.size).to eq(1)
    end

    private

    def normalize_xml(xml)
      xml.gsub(/>\s+</, "><")
        .gsub(/\s+/, " ")
        .gsub(" >", ">")
        .gsub("?><", "?>\n<")
        .strip
    end
  end
end
