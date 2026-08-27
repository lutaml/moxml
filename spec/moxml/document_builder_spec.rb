# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::DocumentBuilder do
  # Issue #124: 0.3.0 deleted the class and NameError'd downstream
  # callers (lutaml-xsd parses XML through this constructor shape).
  describe ".new with a context" do
    it "builds a document from XML content" do
      context = Moxml::Context.new
      builder = described_class.new(context)
      doc = builder.build(<<~XML)
        <person xmlns="http://example.com/test" id="123">
          <name>John Doe</name>
        </person>
      XML

      expect(doc).to be_a(Moxml::Document)
      expect(doc.root.name).to eq("person")
      expect(doc.root["id"]).to eq("123")
      expect(doc.root.children.select(&:element?).map(&:name)).to eq(["name"])
    end

    it "exposes the context it was created with" do
      context = Moxml::Context.new
      builder = described_class.new(context)

      expect(builder.context).to equal(context)
    end

    it "accepts an explicit adapter, matching Context.new(adapter)" do
      context = Moxml::Context.new(:nokogiri)
      doc = described_class.new(context).build("<root><child/></root>")

      expect(doc.context.config.adapter_name).to eq(:nokogiri)
      expect(doc.root.children.select(&:element?).map(&:name)).to eq(["child"])
    end
  end
end
