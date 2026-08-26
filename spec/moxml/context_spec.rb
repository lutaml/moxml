# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Context do
  let(:context) { described_class.new }

  describe "#parse" do
    it "parses XML string" do
      doc = context.parse("<root><child/></root>")
      expect(doc).to be_a(Moxml::Document)
      expect(doc.root.name).to eq("root")
    end
  end

  describe "#config" do
    it "has a configuration" do
      expect(context.config).to be_a(Moxml::Config)
    end
  end

  describe "adapter access" do
    it "provides adapter through config" do
      expect(context.config.adapter).to be_a(Class)
      expect(context.config.adapter.ancestors).to include(Moxml::Adapter::Base)
    end
  end

  describe "#build" do
    it "creates a document via builder DSL" do
      doc = context.build do
        element("root") do
          element("child") do
            text("hello")
          end
        end
      end
      expect(doc).to be_a(Moxml::Document)
      expect(doc.root.name).to eq("root")
    end
  end

  describe "wrapper identity map" do
    it "hands back the same wrapper for the same native" do
      doc = context.parse("<root><item id='1'/></root>")
      first = doc.xpath("//item").first
      second = doc.xpath("//item").first
      expect(first).to equal(second)

      again = doc.root.children.last
      expect(again).to equal(first)
    end

    it "re-keys when refresh_native! swaps the native" do
      doc = context.create_document
      element = doc.create_element("x")
      doc.add_child(element)

      refreshed = doc.root
      expect(refreshed.name).to eq("x")
      expect(context.wrapper_for(refreshed.native)).to equal(refreshed)
    end
  end
end
