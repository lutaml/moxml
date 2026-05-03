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

    it "escapes XML special characters" do
      escaped_doc = context.parse("<root>a &lt; b &amp; c</root>")
      text = escaped_doc.root.children.first
      expect(text.to_xml).to eq("a &lt; b &amp; c")
    end
  end

  describe "#to_s" do
    it "returns text content" do
      text = doc.root.children.first
      expect(text.to_s).to eq("plain text")
    end

    it "is consistent across adapters" do
      Moxml::Adapter::AVALIABLE_ADAPTERS.each do |adapter_name|
        ctx = Moxml.new(adapter_name)
        d = ctx.parse("<root>hello world</root>")
        text = d.root.children.first
        expect(text.to_s).to eq("hello world"),
                             "Text#to_s for #{adapter_name} adapter"
      end
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
