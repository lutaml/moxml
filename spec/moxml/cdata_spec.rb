# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Cdata do
  let(:context) { Moxml.new }
  let(:doc) { context.parse("<root><![CDATA[test data]]></root>") }

  describe "#content" do
    it "returns CDATA content" do
      cdata = doc.root.children.first
      expect(cdata).to be_a(described_class)
      expect(cdata.content).to eq("test data")
    end
  end

  describe "#to_xml" do
    it "serializes to CDATA section" do
      cdata = doc.root.children.first
      expect(cdata.to_xml).to eq("<![CDATA[test data]]>")
    end
  end

  describe "creation" do
    it "creates a CDATA node" do
      cdata = doc.create_cdata("new data")
      expect(cdata).to be_a(described_class)
      expect(cdata.content).to eq("new data")
    end
  end
end
