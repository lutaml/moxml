# frozen_string_literal: true

require "spec_helper"

# leptris-ruby#586 adoption — the flat packet attribute face
# (binding 1.9.406.1): one crossing, interned names, fresh values,
# no per-element memo retention on the binding side. The facade
# listing face stays bare names (uniform with every adapter),
# document order. Older bindings keep the snapshot face
# (ELEMENT_ATTR_SNAPSHOT); the packet path must be stride-identical
# to it — parity is the contract, allocations are the win.
RSpec.describe "leptris element-attribute packet hydration" do
  def bare(pairs)
    pairs.map { |(name, value)| [name.split(":", 2).last, value] }
  end
  let(:ctx) { Moxml.new(:leptris) }

  context "when the packet face is armed (>= 1.9.406.1)" do
    before do
      unless Moxml::Adapter::Leptris::ELEMENT_ATTR_PACKET
        skip "binding #{Leptris::VERSION} has no attribute_packet face"
      end
    end

    it "matches the binding per-attribute face stride for stride" do
      doc = ctx.parse(
        '<root a="1" xml:lang="en" xmlns:ns="urn:u" ns:p="v"/>',
      )
      binding_element = Moxml::Adapter::Leptris.to_binding(doc.root)
      expected = bare(binding_element.attribute_pairs)

      expect(doc.root.attribute_pairs).to eq(expected)
      expect(doc.root.attribute_pairs).to eq(
        [["a", "1"], ["lang", "en"], ["p", "v"]],
      )
    end

    it "keeps document order across plain and prefixed attributes" do
      doc = ctx.parse(
        '<root z="9" xmlns:m="urn:m" m:x="8" k="7"/>',
      )
      expect(doc.root.attribute_pairs.map(&:first)).to eq(
        %w[z x k],
      )
    end

    it "hydrates child elements the same way" do
      doc = ctx.parse('<r><child b="2" c="3"/></r>')
      expect(doc.at("//child").attribute_pairs).to eq(
        [["b", "2"], ["c", "3"]],
      )
    end

    it "yields an empty list for attribute-less elements" do
      doc = ctx.parse("<root/>")
      expect(doc.root.attribute_pairs).to eq([])
    end

    it "mints nothing into the binding identity cache" do
      doc = ctx.parse('<root a="1" b="2"/>')
      binding_element = Moxml::Adapter::Leptris.to_binding(doc.root)
      before = binding_element.document.native_cache.size
      doc.root.attribute_pairs
      expect(binding_element.document.native_cache.size).to eq(before)
    end
  end

  context "with any arm state" do
    it "agrees with the binding per-attribute face" do
      doc = ctx.parse(
        '<root a="1" xml:lang="en" xmlns:ns="urn:u" ns:p="v"/>',
      )
      binding_element = Moxml::Adapter::Leptris.to_binding(doc.root)
      expect(doc.root.attribute_pairs).to eq(
        bare(binding_element.attribute_pairs),
      )
    end
  end
end
