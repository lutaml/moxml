# frozen_string_literal: true

require "spec_helper"

# The COLUMNAR_WALK children map must never serve rows older than a
# completed mutation, through EVERY write lane. This is the memo-version
# law (leptris-ruby#530) applied to the columnar map: the binding
# Document#@version advances on every mutation, so a map primed under
# an older version is stale by construction — independent of which
# adapter seam (or none) happens to drop it.
RSpec.describe "columnar children map invalidation" do
  let(:ctx) { Moxml.new(:leptris) }

  def walk_children(node)
    node.children.map { |c| c.is_a?(Moxml::Element) ? c.name : c.text }
  end

  it "serves fresh rows after content= replaces a child subtree" do
    doc = ctx.parse("<r><a>t1</a><b>t2</b></r>")
    a = doc.root.children.first
    walk_children(a) # prime the columnar map over a's subtree
    a.content = "replaced"
    expect(walk_children(a)).to eq(["replaced"])
    expect(walk_children(doc.root)).to eq(%w[a b])
  end

  it "serves fresh rows after add_element" do
    doc = ctx.parse("<r><a/></r>")
    walk_children(doc.root)
    doc.root.add_element("b", "k" => "v")
    expect(walk_children(doc.root)).to eq(%w[a b])
  end

  it "serves fresh rows after add_next_sibling" do
    doc = ctx.parse("<r><a/></r>")
    a = doc.root.children.first
    walk_children(doc.root)
    a.add_next_sibling("<c/>")
    expect(walk_children(doc.root)).to eq(%w[a c])
  end

  it "serves fresh rows after remove" do
    doc = ctx.parse("<r><a/><b/></r>")
    b = doc.root.children.last
    walk_children(doc.root)
    b.remove
    expect(walk_children(doc.root)).to eq(%w[a])
  end

  it "keeps the primed rows valid when nothing mutated" do
    doc = ctx.parse("<r><a>t1</a><b>t2</b></r>")
    expected = walk_children(doc.root)
    expect(walk_children(doc.root)).to eq(expected)
    expect(walk_children(doc.root)).to eq(expected)
  end
end
