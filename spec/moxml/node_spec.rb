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

  describe "#each" do
    it "yields direct children" do
      children = node.map { |c| c }
      expect(children.size).to eq(1)
      expect(children.first).to be_a(Moxml::Element)
    end

    it "includes Enumerable" do
      expect(node.map(&:name)).to eq(["child"])
    end
  end

  describe "#outer_xml" do
    it "returns same as to_xml" do
      child = node.children.first
      expect(child.outer_xml).to eq(child.to_xml)
    end
  end

  describe "#before" do
    it "adds a node before self" do
      child = node.children.first
      child.before("before")
      siblings = node.children.map(&:content).join
      expect(siblings).to include("before")
    end
  end

  describe "#after" do
    it "adds a node after self" do
      child = node.children.first
      child.after("after")
      expect(node.children.size).to be >= 2
    end
  end

  describe "#blank?" do
    it "returns true for whitespace-only text" do
      doc2 = context.parse("<root>   </root>")
      expect(doc2.root).to be_blank
    end

    it "returns false for non-blank content" do
      expect(node).not_to be_blank
    end
  end

  describe "#content" do
    it "returns empty string on base Node" do
      expect(described_class.new(nil, context).content).to eq("")
    end

    it "returns text on Element" do
      child = node.children.first
      expect(child.content).to eq("text")
    end
  end

  describe "#ancestors" do
    let(:doc) { context.parse("<library><section><book><title>Book 1</title></book></section></library>") }
    let(:title) { doc.at_xpath("//title") }

    it "returns ancestors from parent up to and including the document" do
      ancestors = title.ancestors
      expect(ancestors).to be_a(Moxml::NodeSet)
      expect(ancestors.select(&:element?).map(&:name)).to eq(["book", "section", "library"])
      expect(ancestors[3]).to be_a(Moxml::Document)
    end

    it "returns empty for the document" do
      expect(doc.ancestors).to be_empty
    end

    it "returns the document for the root element" do
      ancestors = doc.root.ancestors
      expect(ancestors.size).to eq(1)
      expect(ancestors.first).to be_a(Moxml::Document)
    end
  end

  describe "#descendants" do
    let(:doc) { context.parse("<section><book><title>Book 1</title></book></section>") }
    let(:section) { doc.at_xpath("//section") }

    it "returns all descendants excluding self" do
      descendants = section.descendants
      expect(descendants).to be_a(Moxml::NodeSet)
      element_names = descendants.select(&:element?).map(&:name)
      expect(element_names).to eq(["book", "title"])
    end

    it "includes text nodes" do
      expect(section.descendants.any?(&:text?)).to be true
    end

    it "returns no elements for a leaf element" do
      expect(doc.at_xpath("//title").descendants.select(&:element?)).to be_empty
    end
  end

  describe "#path" do
    %i[nokogiri oga rexml ox libxml].each do |adapter_name|
      context "with #{adapter_name} adapter" do
        let(:ctx) { Moxml.new(adapter_name) }
        let(:doc) do
          ctx.parse("<library><section><book id='1'/><book id='2'><title>Book 2</title></book></section></library>")
        end
        let(:first_book) { doc.root.children.find(&:element?).children.find { |c| c.element? && c.name == "book" && c["id"] == "1" } }
        let(:second_book) { doc.root.children.find(&:element?).children.find { |c| c.element? && c.name == "book" && c["id"] == "2" } }
        let(:title) { second_book.children.find(&:element?) }

        it "builds the path without a predicate for uniquely named elements" do
          expect(title.path).to eq("/library/section/book[2]/title")
        end

        it "adds a positional predicate for same-named siblings" do
          expect(first_book.path).to eq("/library/section/book[1]")
          expect(second_book.path).to eq("/library/section/book[2]")
        end

        it "locates the node via its path" do
          # Ox translates only a limited XPath subset (no positional predicates)
          skip "ox xpath translation does not support positional predicates" if adapter_name == :ox

          expect(doc.at_xpath(title.path)).to eq(title)
        end

        it "returns / for the document" do
          expect(doc.path).to eq("/")
        end
      end
    end

    it "raises for node types without a path representation" do
      text = doc.root.children.first.children.first
      expect { text.path }.to raise_error(Moxml::NotImplementedError, /element and document/)
    end
  end

  describe "#line_number" do
    %i[nokogiri oga rexml ox libxml].each do |adapter_name|
      tracks_source_lines = adapter_name.eql?(:nokogiri) || adapter_name.eql?(:libxml)
      context "with #{adapter_name} adapter" do
        let(:ctx) { Moxml.new(adapter_name) }
        let(:doc) do
          ctx.parse("<?xml version='1.0'?>\n<library>\n  <book>\n    <title>Book 1</title>\n  </book>\n</library>\n")
        end
        let(:title) { doc.root.children.find(&:element?).children.find(&:element?) }

        if tracks_source_lines
          it "returns the 1-based source line" do
            expect(title.line_number).to eq(4)
          end
        else
          it "returns nil when the adapter does not track lines" do
            expect(title.line_number).to be_nil
          end
        end
      end
    end
  end
end
