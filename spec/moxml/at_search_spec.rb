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

  describe "Node#<< append sugar" do
    it "appends parsed fragments from strings" do
      doc = Moxml.parse("<r/>")
      doc.root << "<a/><b/>"
      expect(doc.root.children.map(&:name)).to eq(%w[a b])
    end

    it "appends plain text as a text node" do
      text_parent = Moxml.parse("<p/>").root
      text_parent << "hello"
      expect(text_parent.text).to eq("hello")
    end

    it "appends nodes" do
      doc = Moxml.parse("<r/>")
      doc.root << Moxml.parse("<b/>").root
      expect(doc.root.children.map(&:name)).to eq(%w[b])
    end

    it "returns self for chaining" do
      doc = Moxml.parse("<r/>")
      expect(doc.root << "<a/>").to be(doc.root)
    end
  end

  describe "Element#delete" do
    it "removes an attribute by name" do
      doc = Moxml.parse("<r annex='yes' id='x'/>")
      doc.root.delete("annex")
      expect(doc.root["annex"]).to be_nil
      expect(doc.root["id"]).to eq("x")
    end
  end

  describe "Element#children=" do
    it "replaces all children with a string" do
      doc = Moxml.parse("<r><old/>text</r>")
      doc.root.children = "<a/><b/>"
      expect(doc.root.children.map(&:name)).to eq(%w[a b])
    end

    it "replaces with a node" do
      doc = Moxml.parse("<r><old/></r>")
      node = Moxml.parse("<x/>").root
      doc.root.children = node
      expect(doc.root.children.map(&:name)).to eq(%w[x])
    end

    it "replaces with an array of nodes" do
      doc = Moxml.parse("<r><old/></r>")
      frag = Moxml.parse("<w><x/><y/></w>").root.children
      doc.root.children = frag
      expect(doc.root.children.map(&:name)).to eq(%w[x y])
    end

    it "invalidates memoized children holders" do
      doc = Moxml.parse("<r><old/></r>")
      root = doc.root
      root.children
      root.children = "<new/>"
      expect(root.children.map(&:name)).to eq(%w[new])
    end
  end

  describe "Element#elements" do
    it "returns only element children" do
      doc = Moxml.parse("<r>text<a/><!-- c --><b/></r>")
      expect(doc.root.elements.map(&:name)).to eq(%w[a b])
      expect(doc.root.element_children.map(&:name)).to eq(%w[a b])
    end

    it "stays fresh across mutations" do
      doc = Moxml.parse("<r><a/></r>")
      root = doc.root
      expect(root.elements.map(&:name)).to eq(%w[a])
      root.add_child(doc.create_element("b"))
      expect(root.elements.map(&:name)).to eq(%w[a b])
    end
  end
end

RSpec.describe "NodeSet#- difference" do
  it "removes nodes present in the other set" do
    doc = Moxml.parse("<r><a/><b/><c/></r>")
    diff = doc.search("//xmlns:*") - doc.search("//xmlns:a")
    expect(diff.map(&:name).sort).to eq(%w[b c])
  end
end

RSpec.describe "NodeSet#to_ary" do
  it "flattens inside arrays" do
    doc = Moxml.parse("<r><a/><b/></r>")
    flat = [doc.root, doc.root.elements].flatten
    expect(flat.map(&:name)).to include("r", "a", "b")
  end
end

RSpec.describe "Node#ancestors(selector)" do
  it "filters ancestors by element name" do
    doc = Moxml.parse("<r><table><tr><td><p/></td></tr></table></r>")
    p_node = doc.at("//p")
    expect(p_node.ancestors("table").map(&:name)).to eq(%w[table])
    expect(p_node.ancestors.map(&:name)).to include("td", "tr", "table")
  end
end

RSpec.describe "Node#next_element/previous_element" do
  it "skips interleaved text nodes" do
    doc = Moxml.parse("<r><a/>text<b/></r>")
    a = doc.at("//a")
    expect(a.next_element.name).to eq("b")
    expect(doc.at("//b").previous_element.name).to eq("a")
  end
end

RSpec.describe "Node#parent= reparenting" do
  it "moves a node under a new parent" do
    doc = Moxml.parse("<r><from><p/></from><to/></r>")
    p_node = doc.at("//p")
    p_node.parent = doc.at("//to")
    expect(doc.at("//to/p")).not_to be_nil
    expect(doc.at("//from/p")).to be_nil
  end
end

RSpec.describe "NodeSet#to_xml" do
  it "serializes the set's members in order" do
    doc = Moxml.parse("<r><a>x</a>tail</r>")
    expect(doc.root.children.to_xml).to eq("<a>x</a>tail")
  end
end

RSpec.describe "Node#add_first_child" do
  it "inserts before existing children and handles empty parents" do
    doc = Moxml.parse("<r><b/></r>")
    doc.root.add_first_child("<a/>")
    expect(doc.root.children.map(&:name)).to eq(%w[a b])
    Moxml.parse("<r/>").root.add_first_child("<x/>")
  end
end

RSpec.describe "Node#remove on a detached node" do
  it "is a no-op returning self (Nokogiri parity)" do
    doc = Moxml.parse("<r><p><c/></p><t/></r>")
    p_node = doc.at("//p")
    t = doc.create_element("d")
    p_node.replace(t)
    expect(p_node.parent).to be_nil
    expect(p_node.remove).to equal(p_node)
    t << p_node
    expect(t.children.map(&:name)).to eq(%w[p])
    expect(doc.at("//t/d/p/c")).not_to be_nil
  end
end

RSpec.describe "Element#replace + re-attach under the replacement" do
  it "does not cycle the tree (leptris stale-run splice)" do
    doc = Moxml.parse("<r><a>x</a><b/></r>")
    a = doc.at("//a")
    t = doc.create_element("t")
    a.replace(t)
    t << a
    expect(doc.root.children.map(&:name)).to eq(%w[t b])
    expect(t.children.map(&:name)).to eq(%w[a])
    expect(doc.at("//t/a/text()").text).to eq("x")
  end
end

RSpec.describe "Node/NodeSet#to_s interpolation" do
  it "serializes instead of Object#to_s" do
    doc = Moxml.parse("<r><a>x</a><b/></r>")
    expect("#{doc.at('//a')}").to eq("<a>x</a>")
    expect("#{doc.root.children}").to eq("<a>x</a><b/>")
  end
end

RSpec.describe "Element#default_namespace=" do
  it "binds the element to the default namespace" do
    doc = Moxml.parse("<r><math><mi>x</mi></math></r>")
    math = doc.at("//math")
    math.default_namespace = "http://www.w3.org/1998/Math/MathML"
    expect(math.namespace_uri.to_s).to eq("http://www.w3.org/1998/Math/MathML")
    expect(math.to_xml).to include('xmlns="http://www.w3.org/1998/Math/MathML"')
  end
end
