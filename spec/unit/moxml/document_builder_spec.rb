# frozen_string_literal: true

require "spec_helper"

# DocumentBuilder is an internal class for parsing
# These tests verify it correctly builds Moxml document from native documents
RSpec.describe Moxml::DocumentBuilder do
  let(:context) { Moxml.new }

  describe "#build" do
    it "builds a Moxml document from native document" do
      native_doc = context.parse("<root><child>content</child></root>").native
      builder = described_class.new(context)
      doc = builder.build(native_doc)

      expect(doc).to be_a(Moxml::Document)
      expect(doc.root.name).to eq("root")
    end
  end

  describe "element handling" do
    it "handles nested elements" do
      native_doc = context.parse("<parent><child1/><child2/></parent>").native
      builder = described_class.new(context)
      doc = builder.build(native_doc)

      expect(doc.root.children.length).to eq(2)
    end
  end
end
