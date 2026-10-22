# frozen_string_literal: true

begin
  require "leptris"
rescue LoadError
  # Leptris gem not available - skip all specs in this file
  return
end

require "spec_helper"

# The iterate-every-result row (perf/xpath-residual): a parentless
# NodeSet over bulk-minted identity natives yields rows in place.
# Wrapping an identity native answers the native itself, so the
# loop only owes the rows their first-touch @context prime — these
# specs pin the contract the fast path must keep: yielded rows are
# fully usable contract nodes, one Ruby object per native address
# across every access path, and non-identity rows still wrap.
RSpec.describe "NodeSet#each identity rows (leptris lane)" do
  let(:ctx) { Moxml.new(:leptris) }
  let(:doc) do
    ctx.parse(<<~XML)
      <root>
        <item id="1">alpha</item>
        <item id="2">beta</item>
      </root>
    XML
  end

  it "yields rows that answer contract reads immediately" do
    rows = doc.xpath("//item").map { |n| [n.name, n.text, n["id"]] }
    expect(rows).to eq([%w[item alpha 1], %w[item beta 2]])
  end

  it "yields rows whose structural reads work without a prior wrap" do
    doc.xpath("//item").each do |n|
      expect(n.parent.name).to eq("root")
      expect(n.document).not_to be_nil
      expect(n.children.map(&:text)).to eq([n.text])
    end
  end

  it "answers one Ruby object per row across every access path" do
    set = doc.xpath("//item")
    each_rows = set.each.to_a
    again = set.each.to_a

    expect(again).to eq(each_rows)
    expect(set[0]).to equal(each_rows[0])
    expect(set[1]).to equal(each_rows[1])
    expect(set.first).to equal(each_rows[0])
    expect(set.to_a).to eq(each_rows)
  end

  it "keeps one object per address across independent queries" do
    first = doc.xpath("//item").to_a
    second = doc.xpath("//item").to_a
    first.zip(second).each { |a, b| expect(a).to equal(b) }
  end

  it "still wraps synthetic attribute rows as Attribute wrappers" do
    names = doc.xpath("//item/@id").map { |n| [n.class, n.name, n.value] }
    expect(names).to eq([
                          [Moxml::Wrappers::Attribute, "id", "1"],
                          [Moxml::Wrappers::Attribute, "id", "2"],
                        ])
  end

  it "keeps element and whitespace-text rows wrapping by kind" do
    kinds = doc.xpath("/root/node()").map(&:class)
    expect(kinds.count { |k| k < Moxml::Element }).to eq(2)
    expect(kinds.count { |k| k < Moxml::Text }).to eq(3)
    expect(kinds).to all(be < Moxml::Node)
  end

  it "parent-carrying sets (children face) still yield usable rows" do
    kinds = []
    doc.root.children.each do |child|
      kinds << child.class
      expect(child.parent_node).not_to be_nil
    end
    expect(kinds.count { |k| k < Moxml::Element }).to eq(2)
  end
end
