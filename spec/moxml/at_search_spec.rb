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

  describe "NodeSet#- difference" do
    it "removes nodes present in the other set" do
      doc = Moxml.parse("<r><a/><b/><c/></r>")
      diff = doc.root.children - doc.search("//a")
      expect(diff.map(&:name).sort).to eq(%w[b c])
    end
  end

  describe "NodeSet#to_ary" do
    it "flattens inside arrays" do
      doc = Moxml.parse("<r><a/><b/></r>")
      flat = [doc.root, doc.root.elements].flatten
      expect(flat.map(&:name)).to include("r", "a", "b")
    end
  end

  describe "Node#ancestors(selector)" do
    it "filters ancestors by element name" do
      doc = Moxml.parse("<r><table><tr><td><p/></td></tr></table></r>")
      p_node = doc.at("//p")
      expect(p_node.ancestors("table").map(&:name)).to eq(%w[table])
      expect(p_node.ancestors.map(&:name)).to include("td", "tr", "table")
    end
  end

  describe "Node#next_element/previous_element" do
    it "skips interleaved text nodes" do
      doc = Moxml.parse("<r><a/>text<b/></r>")
      a = doc.at("//a")
      expect(a.next_element.name).to eq("b")
      expect(doc.at("//b").previous_element.name).to eq("a")
    end
  end

  describe "Node#parent= reparenting" do
    it "moves a node under a new parent" do
      doc = Moxml.parse("<r><from><p/></from><to/></r>")
      p_node = doc.at("//p")
      p_node.parent = doc.at("//to")
      expect(doc.at("//to/p")).not_to be_nil
      expect(doc.at("//from/p")).to be_nil
    end
  end

  describe "NodeSet#to_xml" do
    it "serializes the set's members in order" do
      doc = Moxml.parse("<r><a>x</a>tail</r>")
      expect(doc.root.children.to_xml).to eq("<a>x</a>tail")
    end
  end

  describe "Node#add_first_child" do
    it "inserts before existing children and handles empty parents" do
      doc = Moxml.parse("<r><b/></r>")
      doc.root.add_first_child("<a/>")
      expect(doc.root.children.map(&:name)).to eq(%w[a b])
      Moxml.parse("<r/>").root.add_first_child("<x/>")
    end
  end

  describe "Node#remove on a detached node" do
    it "is a no-op returning self (Nokogiri parity)" do
      doc = Moxml.parse("<r><p><c/></p><t/></r>")
      p_node = doc.at("//p")
      t = doc.create_element("d")
      p_node.replace(t)
      expect(p_node.parent).to be_nil
      expect(p_node.remove).to equal(p_node)
      t << p_node
      expect(t.children.map(&:name)).to eq(%w[p])
      expect(doc.at("//d/p/c")).not_to be_nil
    end
  end

  describe "Element#replace + re-attach under the replacement" do
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

  describe "Node/NodeSet#to_s interpolation" do
    it "serializes instead of Object#to_s" do
      doc = Moxml.parse("<r><a>x</a><b/></r>")
      # rubocop:disable Style/RedundantInterpolation -- the interpolation IS the contract under test
      node = doc.at("//a")
      expect("#{node}").to eq("<a>x</a>")
      children = doc.root.children
      expect("#{children}").to eq("<a>x</a><b></b>")
      # rubocop:enable Style/RedundantInterpolation
    end
  end

  describe "Element#default_namespace=" do
    it "binds the element to the default namespace" do
      doc = Moxml.parse("<r><math><mi>x</mi></math></r>")
      math = doc.at("//math")
      math.default_namespace = "http://www.w3.org/1998/Math/MathML"
      expect(math.namespace_uri.to_s).to eq("http://www.w3.org/1998/Math/MathML")
      expect(math.to_xml).to include('xmlns="http://www.w3.org/1998/Math/MathML"')
    end
  end

  describe "Node#to_str" do
    it "yields the text content" do
      doc = Moxml.parse("<r><s>a<b>c</b>d</s></r>")
      expect(doc.at("//s").to_str).to eq("acd")
      expect(doc.at("//b").to_str).to eq("c")
    end
  end

  describe "Element#content=" do
    it "replaces children with the given text" do
      doc = Moxml.parse("<r><s><b>x</b>y</s></r>")
      s = doc.at("//s")
      s.content = "1 < 2"
      expect(s.children.size).to eq(1)
      expect(s.content).to eq("1 < 2")
      expect(s.to_xml).to eq("<s>1 &lt; 2</s>")
    end
  end

  describe "Node#next/previous readers" do
    it "return adjacent siblings" do
      doc = Moxml.parse("<r><a/>mid<b/></r>")
      a = doc.at("//a")
      expect(a.next.name).to eq("text")
      expect(a.next.next.name).to eq("b")
      expect(doc.at("//b").previous.name).to eq("text")
      expect(doc.at("//b").previous.previous.name).to eq("a")
    end
  end

  describe "Node#path for non-element nodes" do
    it "builds type-test segments" do
      doc = Moxml.parse("<r><p>a<!--c--></p><p>b</p></r>")
      expect(doc.at("//p").path).to eq("/r/p[1]")
      texts = doc.xpath("//p/text()")
      expect(texts[0].path).to eq("/r/p[1]/text()")
      expect(doc.xpath("//p/comment()").first.path).to eq("/r/p[1]/comment()")
    end
  end

  describe "Document#root= native adoption re-points the source wrapper" do
    it "writes through the original wrapper reach the installed tree" do
      ctx = Moxml.new(:leptris)
      other = ctx.parse('<r xmlns="urn:x" a="1"><p>hi<b>t</b></p></r>')
      doc = ctx.create_document
      src_root = other.root
      doc.root = src_root
      # the engine deep-copies; the wrapper now addresses the installed
      # handle — a later write must serialize into the new document
      src_root["a"] = "2"
      expect(doc.to_xml(indent: 0)).to include('a="2"')
      expect(doc.root["a"]).to eq("2")
      expect(doc.root.namespace_uri.to_s).to eq("urn:x")
    end
  end

  describe "Document#root= with a foreign root" do
    it "adopts the subtree from another document" do
      doc = Moxml.parse("<old><x/></old>")
      other = Moxml.parse(%(<r xmlns="urn:x" a="1"><p>hi<b>t</b></p></r>))
      doc.root = other.root
      expect(doc.to_xml(indent: 0).strip)
        .to eq(%(<r xmlns="urn:x" a="1"><p>hi<b>t</b></p></r>))
      expect(doc.root.namespace_uri.to_s).to eq("urn:x")
    end
  end

  describe "String operands are markup, not literal text" do
    it "add_child / add_next_sibling / add_previous_sibling parse strings" do
      doc = Moxml.parse("<r><a/></r>")
      a = doc.at("//a")
      a.add_child("<c/>")
      a.add_next_sibling("<d/>")
      a.add_previous_sibling("<b/>")
      expect(a.children.map(&:name)).to eq(%w[c])
      expect(doc.root.children.map(&:name)).to eq(%w[b a d])
      expect(doc.at("//r/a/c")).not_to be_nil
    end
  end

  describe "Markup-string insertion returns a NodeSet of new nodes" do
    it "add_child / add_next_sibling return the new nodes; nodes return self" do
      doc = Moxml.parse("<r><a/></r>")
      a = doc.at("//a")
      kids = a.add_child("<c1/><c2/>")
      expect(kids).to be_a(Moxml::NodeSet)
      expect(kids.map(&:name)).to eq(%w[c1 c2])
      sibs = a.add_next_sibling("<n1/><n2/>")
      expect(sibs.map(&:name)).to eq(%w[n1 n2])
      expect(doc.root.children.map(&:name)).to eq(%w[a n1 n2])
      prev = a.add_previous_sibling("<p1/><p2/>")
      expect(prev.map(&:name)).to eq(%w[p1 p2])
      expect(doc.root.children.map(&:name)).to eq(%w[p1 p2 a n1 n2])
      expect(a.add_child(doc.at("//p1"))).to equal(a)
    end
  end

  describe "default_namespace= idempotence" do
    it "does not duplicate an identical in-scope default namespace" do
      doc = Moxml.parse(%(<r xmlns="urn:x"><math xmlns="urn:m"/></r>))
      math = doc.at("//m:math", "m" => "urn:m")
      math.default_namespace = "urn:m"
      expect(math.to_xml).to eq(%(<math xmlns="urn:m"></math>))
    end
  end

  describe "xpath with namespace bindings" do
    it "prefixed star and name tests honor the namespace URI" do
      # m must be DECLARED on the element — a bare m:title with only
      # a default xmlns is a no-namespace element whose literal name
      # carries the colon, and no prefix binding can select it.
      doc = Moxml.parse(%(<r><bibdata/><m:title xmlns:m="urn:x"/></r>))
      hits = doc.root.xpath(".//m:*", "m" => "urn:unitsml")
      expect(hits.map(&:name)).to eq([])
      named = doc.root.at_xpath(".//m:title", "m" => "urn:x")
      expect(named&.name).to eq("title")
      none = doc.root.at_xpath(".//m:title", "m" => "urn:unitsml")
      expect(none).to be_nil
    end
  end

  describe "Element#inner_xml" do
    it "serializes the children" do
      doc = Moxml.parse("<r><a>x</a><b/></r>")
      expect(doc.root.inner_xml).to eq("<a>x</a><b/>")
    end
  end

  describe "Node#remove after replace with a parent link" do
    it "is a no-op, not an engine error (stale wrapper parent link)" do
      doc = Moxml.parse("<r><term><p>a</p><note>n</note></term></r>")
      # children walks are parent-aware: the wrapper carries @parent_node
      p_node = doc.at("//term").children.find { |c| c.name == "p" }
      t = doc.create_element("definition")
      p_node.replace(t)
      expect { t << p_node.remove }.not_to raise_error
      expect(doc.at("//term/definition/p")).not_to be_nil
      expect(doc.at("//term/definition/p").text).to eq("a")
    end
  end

  describe "wrapper read memos" do
    it "Element#text memoizes and invalidates on text=/children=" do
      doc = Moxml.parse("<r><a>x<b>y</b>z</a></r>")
      a = doc.at("//a")
      first = a.text
      expect(a.text).to equal(first)
      a.text = "new"
      expect(a.text).to eq("new")
      a.children = "<c>w</c>"
      expect(a.text).to eq("w")
    end

    it "Element#inner_text memoizes and invalidates on child mutations" do
      doc = Moxml.parse("<r><a>x<b>y</b>z</a></r>")
      a = doc.at("//a")
      first = a.inner_text
      expect(a.inner_text).to equal(first)
      a.add_child(doc.create_element("c"))
      expect(a.inner_text).not_to equal(first)
      a.text = "plain"
      expect(a.inner_text).to eq("plain")
    end

    it "Attribute#value memoizes and invalidates on value=" do
      doc = Moxml.parse(%(<r a="1"/>))
      attr = doc.root.attributes.first
      first = attr.value
      expect(attr.value).to equal(first)
      attr.value = "2"
      expect(attr.value).to eq("2")
      expect(doc.root["a"]).to eq("2")
    end
  end

  describe "Text#content memo" do
    it "memoizes and invalidates on content=" do
      doc = Moxml.parse("<r>hello</r>")
      t = doc.root.children.first
      first = t.content
      expect(t.content).to equal(first)
      expect(t.text).to equal(first)
      t.content = "bye"
      expect(t.content).to eq("bye")
    end
  end
end
