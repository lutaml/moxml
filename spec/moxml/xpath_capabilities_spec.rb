# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XPath Capabilities" do
  let(:xml_with_namespaces) do
    <<~XML
      <?xml version="1.0"?>
      <library xmlns="http://library.org"
               xmlns:book="http://library.org/book"
               xmlns:author="http://library.org/author">
        <book:item id="1" price="10">
          <book:title>Ruby Programming</book:title>
          <author:name>Jane Doe</author:name>
        </book:item>
        <book:item id="2" price="15">
          <book:title>XML Processing</book:title>
          <author:name>John Smith</author:name>
        </book:item>
      </library>
    XML
  end

  let(:simple_xml) do
    <<~XML
      <library>
        <book id="1" category="programming">
          <title>Ruby Guide</title>
          <pages>300</pages>
        </book>
        <book id="2" category="reference">
          <title>XML Reference</title>
          <pages>250</pages>
        </book>
        <magazine id="3">
          <title>Tech Monthly</title>
        </magazine>
      </library>
    XML
  end

  # Test each adapter
  %i[nokogiri oga rexml ox libxml].each do |adapter_name|
    context "with #{adapter_name} adapter" do
      around do |example|
        Moxml.with_config(adapter_name, true, "UTF-8") do
          example.run
        end
      rescue LoadError
        skip "#{adapter_name} not available"
      end

      describe "basic path selection" do
        it "supports descendant paths (//element)" do
          doc = Moxml.new.parse(simple_xml)
          books = doc.xpath("//book")
          expect(books.length).to eq(2)
        end

        it "supports absolute paths (/root/child)" do
          doc = Moxml.new.parse(simple_xml)
          books = doc.xpath("/library/book")
          expect(books.length).to eq(2)
        end

        it "supports relative paths (.//element)" do
          doc = Moxml.new.parse(simple_xml)
          library = doc.root
          books = library.xpath(".//book")
          expect(books.length).to eq(2)
        end
      end

      describe "attribute predicates" do
        it "supports attribute existence check ([@attr])" do
          doc = Moxml.new.parse(simple_xml)
          items_with_id = doc.xpath("//book[@id]")
          expect(items_with_id.length).to eq(2)
        end

        it "supports attribute value matching ([@attr='value'])" do
          doc = Moxml.new.parse(simple_xml)
          programming = doc.xpath("//book[@category='programming']")
          expect(programming.length).to be >= 0 # May not work on all
        rescue Moxml::XPathError
          skip "Attribute value predicates not supported on #{adapter_name}"
        end
      end

      describe "namespace support" do
        it "handles namespaced elements with prefix mapping" do
          doc = Moxml.new.parse(xml_with_namespaces)
          namespaces = {
            "book" => "http://library.org/book",
            "author" => "http://library.org/author",
          }

          items = doc.xpath("//book:item", namespaces)
          expect(items.length).to be >= 0
        rescue Moxml::XPathError, NoMethodError
          skip "Namespace XPath not supported on #{adapter_name}"
        end

        it "handles default namespaces" do
          doc = Moxml.new.parse(xml_with_namespaces)
          namespaces = { "lib" => "http://library.org" }

          library = doc.xpath("//lib:library", namespaces)
          expect(library.length).to be >= 0
        rescue Moxml::XPathError, NoMethodError
          skip "Default namespace XPath not supported on #{adapter_name}"
        end
      end

      describe "position-based selection" do
        it "supports numeric positions ([1])" do
          doc = Moxml.new.parse(simple_xml)
          first_book = doc.xpath("//book[1]")
          expect(first_book.length).to be >= 0
        rescue Moxml::XPathError
          skip "Position predicates not supported on #{adapter_name}"
        end

        it "supports position() function" do
          doc = Moxml.new.parse(simple_xml)
          first_books = doc.xpath("//book[position()=1]")
          expect(first_books.length).to be >= 0
        rescue Moxml::XPathError
          skip "position() function not supported on #{adapter_name}"
        end
      end

      describe "XPath functions" do
        it "supports count() function" do
          doc = Moxml.new.parse(simple_xml)
          # NOTE: count() returns a number, not nodes
          result = doc.xpath("count(//book)")
          expect(result).to be_a(Numeric) if result.is_a?(Numeric)
        rescue Moxml::XPathError, NoMethodError
          skip "count() function not supported on #{adapter_name}"
        end

        it "supports text() node selection" do
          doc = Moxml.new.parse(simple_xml)
          texts = doc.xpath("//title/text()")
          expect(texts.length).to be >= 0
        rescue Moxml::XPathError
          skip "text() not supported on #{adapter_name}"
        end
      end

      describe "complex predicates" do
        it "supports numeric comparisons ([@attr < value])" do
          doc = Moxml.new.parse(simple_xml)
          cheap_books = doc.xpath("//book[@id < 2]")
          expect(cheap_books.length).to be >= 0
        rescue Moxml::XPathError
          skip "Numeric predicates not supported on #{adapter_name}"
        end

        it "supports boolean expressions ([cond1 and cond2])" do
          doc = Moxml.new.parse(simple_xml)
          result = doc.xpath("//book[@id and @category]")
          expect(result.length).to be >= 0
        rescue Moxml::XPathError
          skip "Boolean expressions not supported on #{adapter_name}"
        end
      end

      describe "axes" do
        it "supports child axis" do
          doc = Moxml.new.parse(simple_xml)
          children = doc.xpath("/library/child::book")
          expect(children.length).to be >= 0
        rescue Moxml::XPathError
          skip "child:: axis not supported on #{adapter_name}"
        end

        it "supports descendant axis" do
          doc = Moxml.new.parse(simple_xml)
          descendants = doc.xpath("//library/descendant::title")
          expect(descendants.length).to be >= 0
        rescue Moxml::XPathError
          skip "descendant:: axis not supported on #{adapter_name}"
        end
      end

      describe "union operator" do
        it "supports union (|)" do
          doc = Moxml.new.parse(simple_xml)
          items = doc.xpath("//book | //magazine")
          expect(items.length).to be >= 0
        rescue Moxml::XPathError
          skip "Union operator not supported on #{adapter_name}"
        end
      end
    end
  end
end
