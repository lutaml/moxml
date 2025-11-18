# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Document do
  let(:context) { Moxml.new }
  let(:doc) { context.parse("<root/>") }

  describe "document creation" do
    it "creates a document via parsing" do
      expect(doc).to be_a(described_class)
    end

    it "has a context" do
      expect(doc.context).to be_a(Moxml::Context)
    end

    it "has a root element" do
      expect(doc.root).to be_a(Moxml::Element)
      expect(doc.root.name).to eq("root")
    end
  end

  describe "#create_element" do
    it "creates an element" do
      element = doc.create_element("test")
      expect(element).to be_a(Moxml::Element)
      expect(element.name).to eq("test")
    end
  end

  describe "#to_xml" do
    it "serializes to XML" do
      doc = context.parse("<root><child>text</child></root>")
      xml = doc.to_xml
      expect(xml).to include("<root>")
      expect(xml).to include("<child>")
    end
  end

  describe "convenience API methods" do
    describe "#add_element" do
      it "creates and adds element with attributes" do
        fresh_doc = context.create_document
        elem = fresh_doc.add_element("book", id: "123", title: "Ruby")

        expect(elem).to be_a(Moxml::Element)
        expect(elem.name).to eq("book")
        expect(elem["id"]).to eq("123")
        expect(elem["title"]).to eq("Ruby")
        expect(fresh_doc.children).to include(elem)
      end

      it "accepts a block for further customization" do
        fresh_doc = context.create_document
        elem = fresh_doc.add_element("book", id: "123") do |e|
          e.text = "Content"
        end

        expect(elem.text).to eq("Content")
      end

      it "returns the created element" do
        fresh_doc = context.create_document
        elem = fresh_doc.add_element("book")

        expect(elem).to be_a(Moxml::Element)
        expect(elem.name).to eq("book")
      end
    end

    describe "#find" do
      it "finds first element matching xpath" do
        doc = context.parse("<root><book id='1'/><book id='2'/></root>")
        result = doc.find("//book")

        expect(result).to be_a(Moxml::Element)
        expect(result["id"]).to eq("1")
      end

      it "returns nil when not found" do
        result = doc.find("//nonexistent")

        expect(result).to be_nil
      end
    end

    describe "#find_all" do
      it "finds all elements matching xpath" do
        doc = context.parse("<root><book id='1'/><book id='2'/></root>")
        results = doc.find_all("//book")

        expect(results).to be_an(Array)
        expect(results.length).to eq(2)
        expect(results.map { |r| r["id"] }).to eq(%w[1 2])
      end

      it "returns empty array when not found" do
        results = doc.find_all("//nonexistent")

        expect(results).to eq([])
      end
    end
  end
end
