# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Element do
  let(:context) { Moxml.new }
  let(:doc) { context.parse("<root><child>text</child></root>") }
  let(:element) { doc.root }

  describe "#name" do
    it "returns the element name" do
      expect(element.name).to eq("root")
    end
  end

  describe "#children" do
    it "returns child elements" do
      children = element.children
      expect(children).not_to be_empty
      expect(children.first.name).to eq("child")
    end
  end

  describe "#[]" do
    it "gets attribute value" do
      elem = context.parse('<root id="123"/>').root
      expect(elem["id"]).to eq("123")
    end
  end

  describe "#[]=" do
    it "sets attribute value" do
      elem = doc.create_element("test")
      elem["id"] = "456"
      expect(elem["id"]).to eq("456")
    end
  end

  describe "#text" do
    it "returns text content" do
      child = element.children.first
      expect(child.text).to eq("text")
    end
  end

  describe "convenience API methods" do
    describe "#set_attributes" do
      it "sets multiple attributes at once" do
        elem = doc.create_element("book")
        elem.set_attributes(id: "123", title: "Ruby", year: "2024")

        expect(elem["id"]).to eq("123")
        expect(elem["title"]).to eq("Ruby")
        expect(elem["year"]).to eq("2024")
      end

      it "returns self for chaining" do
        elem = doc.create_element("book")
        result = elem.set_attributes(id: "123")

        expect(result).to eq(elem)
      end

      it "handles empty hash" do
        elem = doc.create_element("book")
        expect { elem.set_attributes({}) }.not_to raise_error
      end
    end

    describe "#with_child" do
      it "adds a child and returns self" do
        elem = doc.create_element("parent")
        child = doc.create_element("child")

        result = elem.with_child(child)

        expect(result).to eq(elem)
        expect(elem.children.map(&:name)).to include("child")
      end

      it "can be chained" do
        elem = doc.create_element("parent")
        child1 = doc.create_element("child1")
        child2 = doc.create_element("child2")

        elem.with_child(child1).with_child(child2)

        expect(elem.children.map(&:name)).to eq(%w[child1 child2])
      end
    end

    describe "#find_element" do
      it "finds first element matching xpath" do
        doc = context.parse("<root><book id='1'/><book id='2'/></root>")
        result = doc.root.find_element(".//book")

        expect(result).to be_a(described_class)
        expect(result["id"]).to eq("1")
      end

      it "returns nil when not found" do
        result = element.find_element(".//nonexistent")

        expect(result).to be_nil
      end
    end

    describe "#find_all" do
      it "finds all elements matching xpath" do
        doc = context.parse("<root><book id='1'/><book id='2'/></root>")
        results = doc.root.find_all(".//book")

        expect(results).to be_an(Array)
        expect(results.length).to eq(2)
        expect(results.map { |r| r["id"] }).to eq(%w[1 2])
      end

      it "returns empty array when not found" do
        results = element.find_all(".//nonexistent")

        expect(results).to eq([])
      end
    end

    describe "method chaining" do
      it "chains with_namespace, set_attributes, and with_child" do
        elem = doc.create_element("book")
        child = doc.create_element("title")
        child.text = "Ruby Programming"

        elem
          .with_namespace("dc", "http://purl.org/dc/elements/1.1/")
          .set_attributes(id: "123", type: "technical")
          .with_child(child)

        expect(elem["id"]).to eq("123")
        expect(elem["type"]).to eq("technical")
        expect(elem.children.first.name).to eq("title")
        expect(elem.namespaces.map(&:uri)).to include("http://purl.org/dc/elements/1.1/")
      end
    end
  end

  describe "#append_xml" do
    it "appends a fragment's top-level nodes with entities round-tripped" do
      %w[leptris nokogiri oga rexml].each do |adapter|
        ctx = Moxml.new(adapter.to_sym)
        doc = ctx.parse(%(<root/>))
        result = doc.root.append_xml(%(<a x="1">t1 &amp; u</a><b/>tail))
        expect(result).to equal(doc.root)
        out = doc.to_xml
        expect(out).to include(%(<a x="1">t1 &amp; u</a>))
        expect(out).to include("<b></b>")
        expect(out).to include("tail")
      end
    end

    it "raises AdapterError on the ox adapter" do
      doc = Moxml.new(:ox).parse(%(<root/>))
      expect { doc.root.append_xml(%(<a/>)) }.to raise_error(Moxml::AdapterError, /Ox/)
    end

    it "raises ParseError for non-well-formed fragments" do
      doc = Moxml.new(:leptris).parse(%(<root/>))
      expect { doc.root.append_xml(%(<a><b></a>)) }.to raise_error(Moxml::ParseError)
    end
  end
end
