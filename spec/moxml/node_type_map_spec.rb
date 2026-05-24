# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Node, "node_type_map" do
  it "maps every type symbol to a Node subclass" do
    described_class.node_type_map.each_value do |klass|
      expect(klass < described_class).to be(true), "Expected #{klass} < Moxml::Node"
    end
  end

  it "covers all standard node types" do
    expected = %i[element text cdata comment processing_instruction
                  document declaration doctype attribute entity_reference]
    expect(described_class.node_type_map.keys).to match_array(expected)
  end

  it "is frozen to prevent modification" do
    expect(described_class.node_type_map).to be_frozen
  end

  describe ".wrap" do
    let(:ctx) { Moxml.new(:nokogiri) }

    it "returns nil for nil input" do
      expect(described_class.wrap(nil, ctx)).to be_nil
    end

    it "wraps native nodes using node_type_map" do
      doc = ctx.parse("<root><child>text</child></root>")
      root = doc.root
      expect(root).to be_a(Moxml::Element)

      text_node = root.children.first.children.first
      expect(text_node).to be_a(Moxml::Text)
    end

    it "returns a Node for unknown types" do
      node = described_class.wrap(Object.new, ctx)
      expect(node).to be_a(described_class)
    end
  end
end
