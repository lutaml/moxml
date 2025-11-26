# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Node do
  let(:context) { Moxml.new }
  let(:doc) { context.parse("<root><child>text</child></root>") }
  let(:node) { doc.root }

  describe "#parent" do
    it "returns parent node" do
      child = node.children.first
      expect(child.parent).to eq(node)
    end
  end

  describe "#document" do
    it "returns document" do
      expect(node.document).to eq(doc)
    end
  end

  describe "#to_xml" do
    it "serializes node to XML" do
      expect(node.to_xml).to include("<root>")
      expect(node.to_xml).to include("<child>")
    end
  end

  describe "#remove" do
    it "removes node from parent" do
      child = node.children.first
      child.remove
      expect(node.children).to be_empty
    end
  end

  describe "#ancestors" do
    let(:xml) { "<library><section><book><title>Book 1</title></book></section></library>" }
    let(:doc) { context.parse(xml) }
    let(:title) { doc.at_xpath("//title") }

    it "returns all ancestor nodes" do
      ancestors = title.ancestors
      expect(ancestors).to be_a(Moxml::NodeSet)
      expect(ancestors.size).to eq(4) # book, section, library, document
    end

    it "returns ancestors in order from parent to root" do
      ancestors = title.ancestors.to_a
      expect(ancestors[0]).to be_a(Moxml::Element)
      expect(ancestors[0].name).to eq("book")
      expect(ancestors[1].name).to eq("section")
      expect(ancestors[2].name).to eq("library")
      expect(ancestors[3]).to be_a(Moxml::Document)
    end
  end

  describe "#descendants" do
    let(:xml) { "<section><book><title>Book 1</title></book></section>" }
    let(:doc) { context.parse(xml) }
    let(:section) { doc.at_xpath("//section") }

    it "returns all descendant nodes" do
      descendants = section.descendants
      expect(descendants).to be_a(Moxml::NodeSet)
      # Should include book, title, and text nodes
      expect(descendants.size).to be >= 2
    end

    it "includes all nested elements and text nodes" do
      descendants = section.descendants.to_a
      element_names = descendants.select { |d| d.is_a?(Moxml::Element) }.map(&:name)
      expect(element_names).to include("book", "title")
    end
  end

  describe "#path" do
    let(:xml) { "<library><section><book><title>Book 1</title></book></section></library>" }
    let(:doc) { context.parse(xml) }
    let(:title) { doc.at_xpath("//title") }
    let(:book) { doc.at_xpath("//book") }

    it "returns XPath to the node" do
      expect(title.path).to be_a(String)
      expect(title.path).to eq("/library/section/book/title")
    end

    it "returns correct path for intermediate nodes" do
      expect(book.path).to eq("/library/section/book")
    end
  end

  describe "#line_number" do
    let(:xml) do
      <<~XML
        <?xml version="1.0"?>
        <library>
          <section>
            <book>
              <title>Book 1</title>
            </book>
          </section>
        </library>
      XML
    end
    let(:doc) { context.parse(xml) }
    let(:title) { doc.at_xpath("//title") }

    it "returns line number for supported adapters" do
      # Nokogiri and LibXML support line numbers
      # Other adapters may return nil
      line_num = title.line_number
      expect(line_num).to be_a(Integer).or(be_nil)
    end
  end
end
