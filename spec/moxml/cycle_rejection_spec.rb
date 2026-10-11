# frozen_string_literal: true

require "spec_helper"

# Engine 1.9.339 (leptris#1640): reparenting a node into its own
# descendant subtree is rejected (LEPTRIS_ERROR_INVALID_ARG) —
# previously the edge built a parent cycle and the next serialize
# recursed unbounded (the windows fast_element_xml segv family,
# ASAN-reproduced). The moxml contract: the mutation RAISES and the
# tree is untouched — never a corrupt-then-crash tree.
RSpec.describe "cycle-creating reparents (engine 1.9.339+)" do
  # Nokogiri raises but MOVES the argument (no tree-intact
  # guarantee) — the untouched-tree contract is the engine's.
  describe "on leptris" do
    let(:ctx) { Moxml.new(:leptris) }

    it "rejects appending an ancestor into its descendant" do
      doc = ctx.parse("<r><a><b>x</b></a></r>")
      a = doc.at("//a")
      before = doc.to_xml
      expect { a.add_child(doc.root) }.to raise_error(StandardError)
      expect(doc.to_xml).to eq(before)
    end

    it "rejects the replace shape of the same cycle" do
      doc = ctx.parse("<r><a><b><c/></b></a></r>")
      b = doc.at("//b")
      before = doc.to_xml
      expect { b.add_child(doc.root) }.to raise_error(StandardError)
      expect(doc.to_xml).to eq(before)
    end
  end
end
