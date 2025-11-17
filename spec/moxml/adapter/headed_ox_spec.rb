# frozen_string_literal: true

require "spec_helper"

# Ensure HeadedOx adapter is loaded
Moxml::Adapter.load(:headed_ox)

RSpec.describe Moxml::Adapter::HeadedOx do
  let(:adapter) { described_class }
  let(:xml) do
    <<~XML
      <root>
        <book price="10">
          <title>Book 1</title>
          <author>Author A</author>
        </book>
        <book price="20">
          <title>Book 2</title>
          <author>Author B</author>
        </book>
        <book price="30">
          <title>Book 3</title>
          <author>Author C</author>
        </book>
      </root>
    XML
  end

  describe ".parse" do
    it "parses XML using Ox" do
      doc = adapter.parse(xml)

      expect(doc).to be_a(Moxml::Document)
      expect(doc.root.name).to eq("root")
    end
  end

  describe ".xpath" do
    let(:doc) { adapter.parse(xml) }

    it "executes simple XPath queries" do
      result = adapter.xpath(doc, "/root/book")

      expect(result).to be_a(Moxml::NodeSet)
      expect(result.size).to eq(3)
    end

    it "executes XPath with numeric predicates" do
      result = adapter.xpath(doc, "//book[@price < 25]")

      expect(result.size).to eq(2)
    end

    it "executes XPath with string predicates" do
      result = adapter.xpath(doc, "//book[@price='20']")

      expect(result.size).to eq(1)
    end

    it "executes XPath with functions" do
      result = adapter.xpath(doc, "count(//book)")

      expect(result).to eq(3.0)
    end

    it "executes complex XPath with paths" do
      result = adapter.xpath(doc, "//book[@price < 25]/title")

      expect(result.size).to eq(2)
      expect(result.map(&:text)).to contain_exactly("Book 1", "Book 2")
    end

    it "supports XPath string functions in predicates" do
      result = adapter.xpath(doc, "//book[contains(title, '2')]")

      expect(result.size).to eq(1)
      expect(result.first.xpath("title").first.text).to eq("Book 2")
    end

    it "supports XPath position functions" do
      result = adapter.xpath(doc, "//book[position() = 2]")

      expect(result.size).to eq(1)
      expect(result.first.xpath("title").first.text).to eq("Book 2")
    end

    it "supports descendant axis" do
      result = adapter.xpath(doc, "//title")

      expect(result.size).to eq(3)
    end

    it "supports attribute axis" do
      result = adapter.xpath(doc, "//book/@price")

      expect(result.size).to eq(3)
      expect(result.map(&:value)).to contain_exactly("10", "20", "30")
    end

    it "supports parent axis" do
      title = adapter.xpath(doc, "//title").first
      result = adapter.xpath(title, "parent::book")

      expect(result.size).to eq(1)
      expect(result.first.name).to eq("book")
    end

    it "handles namespace queries" do
      ns_xml = '<root xmlns:ns="http://example.com"><ns:item/></root>'
      ns_doc = adapter.parse(ns_xml)

      result = adapter.xpath(
        ns_doc,
        "//ns:item",
        { "ns" => "http://example.com" }
      )

      expect(result.size).to eq(1)
    end

    it "returns non-node values directly" do
      result = adapter.xpath(doc, "string(//book[1]/title)")

      expect(result).to eq("Book 1")
    end

    it "handles boolean results" do
      result = adapter.xpath(doc, "boolean(//book)")

      expect(result).to be true
    end

    it "wraps error with XPathError" do
      expect do
        adapter.xpath(doc, "invalid[[[syntax")
      end.to raise_error(Moxml::XPathError)
    end
  end

  describe ".at_xpath" do
    let(:doc) { adapter.parse(xml) }

    it "returns first matching node" do
      result = adapter.at_xpath(doc, "//book")

      expect(result).to be_a(Moxml::Element)
      expect(result.name).to eq("book")
    end

    it "returns nil when no match" do
      result = adapter.at_xpath(doc, "//nonexistent")

      expect(result).to be_nil
    end

    it "returns scalar values directly" do
      result = adapter.at_xpath(doc, "count(//book)")

      expect(result).to eq(3.0)
    end
  end

  describe ".xpath_supported?" do
    it "returns true" do
      expect(adapter.xpath_supported?).to be true
    end
  end

  describe ".capabilities" do
    it "reports full XPath support" do
      caps = adapter.capabilities

      expect(caps[:xpath_full]).to be true
      expect(caps[:xpath_axes]).to eq(:all)
      expect(caps[:xpath_functions]).to eq(:all)
      expect(caps[:xpath_predicates]).to be true
      expect(caps[:xpath_namespaces]).to be true
      expect(caps[:xpath_variables]).to be true
    end

    it "inherits Ox adapter capabilities" do
      caps = adapter.capabilities

      # Should have parsing capability from Ox
      expect(caps).to have_key(:parse)
    end
  end

  describe "XPath function support" do
    let(:doc) { adapter.parse(xml) }

    context "string functions" do
      it "supports string()" do
        result = adapter.xpath(doc, "string(//book[1]/title)")
        expect(result).to eq("Book 1")
      end

      it "supports concat()" do
        result = adapter.xpath(doc, "concat('Price: ', //book[1]/@price)")
        expect(result).to eq("Price: 10")
      end

      it "supports contains()" do
        result = adapter.xpath(doc, "//book[contains(title, 'Book')]")
        expect(result.size).to eq(3)
      end

      it "supports starts-with()" do
        result = adapter.xpath(doc, "//book[starts-with(title, 'Book')]")
        expect(result.size).to eq(3)
      end

      it "supports substring()" do
        result = adapter.xpath(doc, "substring('Hello World', 7)")
        expect(result).to eq("World")
      end

      it "supports string-length()" do
        result = adapter.xpath(doc, "string-length('Hello')")
        expect(result).to eq(5.0)
      end

      it "supports normalize-space()" do
        result = adapter.xpath(doc, "normalize-space('  hello  world  ')")
        expect(result).to eq("hello world")
      end
    end

    context "numeric functions" do
      it "supports number()" do
        result = adapter.xpath(doc, "number(//book[1]/@price)")
        expect(result).to eq(10.0)
      end

      it "supports sum()" do
        result = adapter.xpath(doc, "sum(//book/@price)")
        expect(result).to eq(60.0)
      end

      it "supports count()" do
        result = adapter.xpath(doc, "count(//book)")
        expect(result).to eq(3.0)
      end

      it "supports floor()" do
        result = adapter.xpath(doc, "floor(3.7)")
        expect(result).to eq(3.0)
      end

      it "supports ceiling()" do
        result = adapter.xpath(doc, "ceiling(3.2)")
        expect(result).to eq(4.0)
      end

      it "supports round()" do
        result = adapter.xpath(doc, "round(3.5)")
        expect(result).to eq(4.0)
      end
    end

    context "boolean functions" do
      it "supports boolean()" do
        result = adapter.xpath(doc, "boolean(//book)")
        expect(result).to be true
      end

      it "supports not()" do
        result = adapter.xpath(doc, "not(false())")
        expect(result).to be true
      end

      it "supports true()" do
        result = adapter.xpath(doc, "true()")
        expect(result).to be true
      end

      it "supports false()" do
        result = adapter.xpath(doc, "false()")
        expect(result).to be false
      end
    end

    context "node functions" do
      it "supports name()" do
        result = adapter.xpath(doc, "name(//book[1])")
        expect(result).to eq("book")
      end

      it "supports local-name()" do
        result = adapter.xpath(doc, "local-name(//book[1])")
        expect(result).to eq("book")
      end
    end

    context "position functions" do
      it "supports position()" do
        result = adapter.xpath(doc, "//book[position() = 2]")
        expect(result.size).to eq(1)
      end

      it "supports last()" do
        result = adapter.xpath(doc, "//book[position() = last()]")
        expect(result.size).to eq(1)
        expect(result.first.xpath("title").first.text).to eq("Book 3")
      end
    end
  end
end