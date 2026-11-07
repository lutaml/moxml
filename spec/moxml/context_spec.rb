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

  describe "#parse_html" do
    it "delegates to the adapter's HTML mode" do
      ctx = Moxml.new(:nokogiri)
      doc = ctx.parse_html(%(<p>x</p>))
      expect(doc.root.name).to eq("html")
    end

    it "raises Moxml::AdapterError on adapters without an HTML mode" do
      ctx = Moxml.new(:ox)
      expect { ctx.parse_html(%(<p>x</p>)) }.to raise_error(Moxml::AdapterError, /not supported/)
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

      # Exercise the swap explicitly: the map must answer the wrapper
      # under its CURRENT native after refresh_native!. (Probing the
      # pre-swap mint instead raced the wrap path — identity mints
      # register the map only when the canonical fast path was not
      # taken, which made the assertion order-sensitive.)
      replacement = doc.create_element("y")
      refreshed.refresh_native!(replacement.native)
      expect(context.wrapper_for(replacement.native)).to equal(refreshed)
    end
  end
end
