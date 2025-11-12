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
end
