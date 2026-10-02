# frozen_string_literal: true

require "spec_helper"

# moxml#311: the native and binding layers hold separate Ruby objects
# over one C node. An xpath-resolved node that failed to resolve to
# the tree-walk identity carried no parent link, so sibling inserts
# through it never invalidated the memoized children of wrappers
# handed out before the query — the insert serialized but stayed
# invisible through parent.children.
RSpec.describe "leptris xpath nodes resolve canonical identity" do
  let(:ctx) { Moxml.new(:leptris) }
  let(:doc) { ctx.parse("<r><a>t</a>\n<b/></r>") }

  it "at_xpath returns the walked wrapper" do
    root = doc.root
    walked = root.children.first
    expect(root.at_xpath("a")).to be(walked)
  end

  it "xpath list results resolve canonical identity" do
    root = doc.root
    walked = root.children.first
    expect(root.xpath("a").first).to be(walked)
  end

  it "namespace-bound at_xpath resolves canonical identity" do
    root = doc.root
    walked = root.children.first
    expect(root.at_xpath("a", "xmlns" => "http://x")).to be(walked)
  end

  it "sibling insert through at_xpath resolves in parent.children" do
    root = doc.root
    root.children
    a = root.at_xpath("a")
    a.add_next_sibling(ctx.parse_fragment("<x/>").first)
    expect(root.children.map(&:name)).to eq(%w[a x text b])
  end

  it "sibling insert through the engine path resolves in parent.children" do
    root = doc.root
    root.children
    walked = root.children.first
    a = walked.at_xpath("self::a[parent::r]")
    a.add_next_sibling(ctx.parse_fragment("<x/>").first)
    expect(root.children.map(&:name)).to eq(%w[a x text b])
  end
end
