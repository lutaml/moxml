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
end
