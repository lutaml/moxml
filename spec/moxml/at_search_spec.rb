# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Nokogiri-compatible at/search sugar" do
  let(:doc) do
    Moxml.parse(<<~XML)
      <root xmlns="http://example.com/ns">
        <item id="a"><name>one</name></item>
        <item id="b"><name>two</name></item>
      </root>
    XML
  end

  it "at returns the first match like Nokogiri" do
    node = doc.at("//xmlns:item")
    expect(node["id"]).to eq("a")
  end

  it "at on document delegates to root search" do
    expect(doc.at("//xmlns:name").text).to eq("one")
  end

  it "search returns all matches" do
    expect(doc.search("//xmlns:item").size).to eq(2)
  end

  it "at returns nil when nothing matches" do
    expect(doc.at("//xmlns:missing")).to be_nil
  end

  it "at works on element nodes" do
    item = doc.at("//xmlns:item[@id='b']")
    expect(item.at("xmlns:name").text).to eq("two")
  end
end

RSpec.describe "Node#traverse" do
  it "yields depth-first in document order" do
    doc = Moxml.parse("<r><a><b/></a><c/></r>")
    names = []
    doc.traverse { |n| names << n.name if n.respond_to?(:name) }
    expect(names.first(4)).to eq(%w[r a b c])
  end
end

RSpec.describe "Node#next=/previous=" do
  it "insert a sibling after/before via assignment" do
    doc = Moxml.parse("<r><a/><b/></r>")
    a = doc.at("//a")
    a.next = "<x/>"
    expect(doc.root.children.map(&:name).compact).to eq(%w[a x b])
    b = doc.at("//b")
    b.previous = "<y/>"
    expect(doc.root.children.map(&:name).compact).to eq(%w[a x y b])
  end
end

RSpec.describe "sibling inserts invalidate the parent children cache" do
  it "next= is visible through parent.children when siblings are text" do
    doc = Moxml.parse("<r><a/>\n<b/></r>")
    doc.at("//a").next = "<x/>"
    expect(doc.root.children.map(&:name)).to eq(%w[a text x text b].map { |n| n == "text" ? "text" : n })
    expect(doc.at("//x")).not_to be_nil
  end
end

RSpec.describe "children memo invalidation via generation" do
  it "duality-proof: insert visible through a wrapper that memoized earlier" do
    ctx = Moxml.new(:leptris)
    doc = ctx.parse("<r><a/>\n<b/></r>")
    doc.root.children.map(&:name)            # memoize on the root wrapper
    a = doc.at("//a")                        # possibly a different wrapper instance
    a.next = "<x/>"
    expect(doc.root.children.map(&:name)).to eq(%w[a text x text b])
  end
end
