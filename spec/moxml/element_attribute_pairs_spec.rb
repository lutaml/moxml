# frozen_string_literal: true

require "spec_helper"

# Element#attribute_pairs adapter-contract conformance
# (leptris-ruby#278): pairs must equal what the node path yields —
# attributes.map { |a| [a.name, a.value.to_s] } — on every adapter,
# whether the adapter answers through a bulk C face (leptris >=
# 1.9.208.1) or derives from #attributes.
RSpec.describe Moxml::Element do
  let(:xml) do
    '<catalog><record id="r0" kind="k0"><field name="f0" unit="u0">v</field></record></catalog>'
  end

  ADAPTERS = %i[leptris nokogiri ox oga rexml libxml].freeze # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration

  def with_adapter(name)
    ctx = Moxml.new(name)
    yield ctx
  rescue StandardError, LoadError
    skip "adapter #{name} unavailable"
  end

  it "matches the node path on every available adapter" do
    results = ADAPTERS.filter_map do |name|
      with_adapter(name) do |ctx|
        root = ctx.parse(xml).root
        [name, root.attribute_pairs]
      end
    end
    expect(results).not_to be_empty

    results.each do |name, pairs|
      with_adapter(name) do |ctx|
        root = ctx.parse(xml).root
        node_derived = root.attributes.map { |a| [a.name, a.value.to_s] }
        expect(pairs).to eq(node_derived),
                         "#{name}: #{pairs.inspect} vs #{node_derived.inspect}"
      end
    end
  end

  context "when memoized" do
    it "returns the same object on repeated reads" do
      with_adapter(:leptris) do |ctx|
        root = ctx.parse(xml).root
        expect(root.attribute_pairs).to equal(root.attribute_pairs)
      end
    end

    it "refreshes after a value write" do
      with_adapter(:leptris) do |ctx|
        root = ctx.parse(xml).root
        before = root.attribute_pairs
        root["id"] = "r9"
        expect(root.attribute_pairs).not_to equal(before)
        expect(root.attribute_pairs).to include(["id", "r9"])
      end
    end
  end
end
