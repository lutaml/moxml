# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Nokogiri-compatible node sugar" do
  describe "at/search" do
    let(:doc) do
      Moxml.parse(<<~XML)
        <root xmlns="http://example.com/ns">
          <item id="a"><name>one</name></item>
          <item id="b"><name>two</name></item>
        </root>
      XML
    end
    let(:ns) { { "xmlns" => "http://example.com/ns" } }

    it "at returns the first match like Nokogiri" do
      node = doc.at("//xmlns:item", ns)
      expect(node["id"]).to eq("a")
    end

    it "at on document delegates to root search" do
      expect(doc.at("//xmlns:name", ns).text).to eq("one")
    end

    it "search returns all matches" do
      expect(doc.search("//xmlns:item", ns).size).to eq(2)
    end

    it "at returns nil when nothing matches" do
      expect(doc.at("//xmlns:missing", ns)).to be_nil
    end

    it "at works on element nodes" do
      item = doc.at("//xmlns:item[@id='b']", ns)
      expect(item.at("xmlns:name", ns).text).to eq("two")
    end
  end

  describe "Node#traverse" do
    it "yields depth-first in document order from an element" do
      doc = Moxml.parse("<r><a><b/></a><c/></r>")
      names = []
      doc.root.traverse { |n| names << n.name }
      expect(names).to eq(%w[r a b c])
    end

    it "yields the document first from a document traversal" do
      doc = Moxml.parse("<r><a/></r>")
      names = []
      doc.traverse { |n| names << n.name }
      expect(names).to eq(%w[document r a])
    end
  end

  describe "Node#next=/previous=" do
    it "insert a sibling after/before via assignment" do
      doc = Moxml.parse("<r><a/><b/></r>")
      a = doc.at("//a")
      a.next = "<x/>"
      expect(doc.root.children.map(&:name)).to eq(%w[a x b])
      b = doc.at("//b")
      b.previous = "<y/>"
      expect(doc.root.children.map(&:name)).to eq(%w[a x y b])
    end
  end

  describe "sibling inserts invalidate the parent children cache" do
    it "next= is visible through parent.children when siblings are text" do
      doc = Moxml.parse("<r><a/>\n<b/></r>")
      doc.at("//a").next = "<x/>"
      expect(doc.root.children.map(&:name)).to eq(%w[a x text b])
      expect(doc.at("//x")).not_to be_nil
    end

    it "duality-proof: insert visible through a wrapper that memoized earlier" do
      ctx = Moxml.new(:leptris)
      doc = ctx.parse("<r><a/>\n<b/></r>")
      doc.root.children.map(&:name)          # memoize on the root wrapper
      a = doc.at("//a")                      # possibly a different wrapper instance
      a.next = "<x/>"
      expect(doc.root.children.map(&:name)).to eq(%w[a x text b])
    end
  end
end

RSpec.describe "Node#<< append sugar" do
  it "appends nodes and strings" do
    doc = Moxml.parse("<r/>")
    doc.root << "<a/>"
    doc.root << Moxml.parse("<b/>").root
    expect(doc.root.children.map(&:name)).to eq(%w[a b])
    text_parent = Moxml.parse("<p/>").root
    text_parent << "hello"
    expect(text_parent.text).to eq("hello")
  end
end
