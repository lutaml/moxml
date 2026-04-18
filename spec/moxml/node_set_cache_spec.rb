# frozen_string_literal: true

require "spec_helper"
require "support/allocation_helper"

# NodeSet wrap caching correctness tests — these run in CI by default.
# Verifies that NodeSet per-index wrap caching works correctly across adapters.
RSpec.describe "Moxml NodeSet wrap caching" do
  shared_examples "cached NodeSet wraps" do |adapter_name|
    let(:ctx) { Moxml::Context.new(adapter_name) }
    let(:xml) { "<root><a/><b/><c/></root>" }
    let(:doc) { ctx.parse(xml) }

    describe "NodeSet#each caching" do
      it "returns the same wrapper object on repeated iteration" do
        root = doc.root
        first_pass = root.children.to_a
        second_pass = root.children.to_a
        # Since children itself is cached, the same NodeSet is returned.
        # Within that NodeSet, wrapped nodes should be cached.
        first_pass.each_with_index do |node, i|
          expect(node).to equal(second_pass[i])
        end
      end

      it "returns consistent node names" do
        children = doc.root.children
        names = children.map(&:name)
        expect(names).to eq(%w[a b c])
      end
    end

    describe "NodeSet#[] caching" do
      it "returns the same wrapper for the same index" do
        children = doc.root.children
        first = children[0]
        second = children[0]
        expect(first).to equal(second)
      end

      it "returns the same wrapper from #[] as from #each" do
        children = doc.root.children
        from_each = children.to_a[1]
        from_index = children[1]
        expect(from_each).to equal(from_index)
      end
    end

    describe "NodeSet#first/#last caching" do
      it "returns the same wrapper from #first as from #[0]" do
        children = doc.root.children
        expect(children.first).to equal(children[0])
      end

      it "returns the same wrapper from #last as from #[-1]" do
        children = doc.root.children
        last_idx = children.size - 1
        expect(children.last).to equal(children[last_idx])
      end
    end

    describe "NodeSet mutation" do
      it "appends to cache correctly" do
        ns = doc.root.children
        initial_size = ns.size
        ns << ctx.parse("<d/>").root
        expect(ns.size).to eq(initial_size + 1)
        expect(ns[initial_size].name).to eq("d")
      end

      it "deletes from cache correctly" do
        ns = doc.root.children
        first_child = ns[0]
        ns.delete(first_child)
        expect(ns.size).to eq(2)
        expect(ns[0].name).to eq("b")
      end
    end
  end

  AllocationHelper::GUARDED_ADAPTERS.each do |adapter_name|
    describe "#{adapter_name} adapter" do
      before(:all) do
        skip("#{adapter_name} adapter not available") unless AllocationHelper.adapter_available?(adapter_name)
      end

      it_behaves_like "cached NodeSet wraps", adapter_name
    end
  end
end
