# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Builder do
  let(:context) { Moxml.new }

  describe "#document" do
    it "exposes the underlying document via document accessor" do
      builder = described_class.new(context)
      expect(builder.document).to be_a(Moxml::Document)
    end

    it "exposes the underlying document via doc alias" do
      builder = described_class.new(context)
      expect(builder.doc).to be_a(Moxml::Document)
      expect(builder.doc).to equal(builder.document)
    end

    it "returns the same document before and after build" do
      builder = described_class.new(context)
      doc_before = builder.document
      builder.build do
        element "root"
      end
      expect(builder.document).to equal(doc_before)
    end
  end

  describe "#build" do
    it "builds a document with DSL" do
      doc = described_class.new(context).build do
        element "root" do
          element "child" do
            text "text"
          end
        end
      end

      expect(doc).to be_a(Moxml::Document)
      expect(doc.root.name).to eq("root")
    end

    it "creates nested elements" do
      doc = described_class.new(context).build do
        element "parent" do
          element "child1"
          element "child2"
        end
      end

      expect(doc.root.children.length).to eq(2)
    end
  end
end
