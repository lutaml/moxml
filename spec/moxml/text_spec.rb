# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Text do
  let(:context) { Moxml.new }
  let(:doc) { context.parse("<root>plain text</root>") }

  describe "#content" do
    it "returns text content" do
      text = doc.root.children.first
      expect(text).to be_a(described_class)
      expect(text.content).to eq("plain text")
    end
  end

  describe "#to_xml" do
    it "returns XML representation" do
      text = doc.root.children.first
      expect(text.to_xml).to eq("plain text")
    end
  end

  describe "creation" do
    it "creates a text node" do
      text = doc.create_text("new text")
      expect(text).to be_a(described_class)
      expect(text.content).to eq("new text")
    end
  end
end
