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

    it "uses LF line ending by default" do
      xml = doc.to_xml
      expect(xml).to include("\n")
      expect(xml).not_to include("\r\n")
    end

    it "applies CRLF line ending from config" do
      context.config.default_line_ending = Moxml::Config::LINE_ENDING_CRLF
      xml = doc.to_xml
      expect(xml).to include("\r\n")
    end

    it "allows per-call line ending override" do
      xml = doc.to_xml(line_ending: Moxml::Config::LINE_ENDING_CRLF)
      expect(xml).to include("\r\n")
    end

    it "does not convert when already LF" do
      xml = doc.to_xml(line_ending: Moxml::Config::LINE_ENDING_LF)
      expect(xml).to include("\n")
      expect(xml).not_to include("\r\n")
    end

    it "applies CRLF to indented output" do
      context.config.default_line_ending = Moxml::Config::LINE_ENDING_CRLF
      xml = doc.to_xml(indent: 2)
      expect(xml).to include("\r\n")
      expect(xml).not_to match(/(?<!\r)\n/)
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
