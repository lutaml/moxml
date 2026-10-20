# frozen_string_literal: true

require "spec_helper"

# moxml#375 — element hydration through the binding's
# attributes_snapshot face (libleptris 1.9.353, engine
# leptris#1689): one crossing for every attribute instead of one
# per attribute. The facade listing face is bare names (uniform with
# every adapter, and with Attribute#name), document order, fresh
# values.
RSpec.describe "leptris element-attribute snapshot hydration" do
  def bare(pairs)
    pairs.map { |(name, value)| [name.split(":", 2).last, value] }
  end
  let(:ctx) { Moxml.new(:leptris) }

  context "when the snapshot face is armed (>= 1.9.353.0)" do
    before do
      unless Moxml::Adapter::Leptris::ELEMENT_ATTR_SNAPSHOT
        skip "binding #{Leptris::VERSION} has no attributes_snapshot face"
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

    it "keeps the per-attribute face's memoized-read semantics" do
      doc = ctx.parse('<root a="1"/>')
      first = doc.root.attribute_pairs
      first[0][1] << "mutated"

      # The wrapper memoizes attribute reads; the snapshot path
      # preserves that (values are shared across reads exactly as
      # the binding face's memo does).
      expect(doc.root.attribute_pairs).to eq([["a", "1mutated"]])
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
