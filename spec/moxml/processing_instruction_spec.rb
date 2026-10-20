# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::ProcessingInstruction do
  let(:context) { Moxml.new }
  let(:doc) do
    context.parse('<?xml version="1.0"?><?xml-stylesheet type="text/xsl" href="style.xsl"?><root/>')
  end

  describe "#target" do
    it "returns PI target" do
      pi = doc.children.find { |n| n.is_a?(described_class) }
      expect(pi.target).to eq("xml-stylesheet")
    end
  end

  describe "#content" do
    it "returns PI content" do
      pi = doc.children.find { |n| n.is_a?(described_class) }
      expect(pi.content).to include("type=")
      expect(pi.content).to include("href=")
    end

    it "answers the empty string for a PI with no data on every adapter" do
      Moxml::Adapter::AVAILABLE_ADAPTERS.each do |name|
        parsed = Moxml.new(name).parse("<r><?pi?></r>")
        pi = parsed.children.first.children
          .find { |n| n.is_a?(described_class) }
        expect(pi.content).to eq(""), "empty PI content on #{name}"
      end
    end
  end

  describe "creation" do
    it "creates a processing instruction" do
      pi = doc.create_processing_instruction("target", "content")
      expect(pi).to be_a(described_class)
      expect(pi.target).to eq("target")
      expect(pi.content).to eq("content")
    end
  end
end
