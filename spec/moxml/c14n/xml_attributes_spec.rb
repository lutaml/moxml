# frozen_string_literal: true

require "spec_helper"
require "moxml/c14n"

# xml:lang and xml:space are "simple inheritable" attributes per W3C C14N
# 1.1 §2.4. When an element is in the node-set but an ancestor is not,
# the canonical form inherits these attributes from the nearest ancestor
# in which they were declared.
#
# These specs exercise the inclusive behavior at full-document
# canonicalization (where everything is in the set, so inheritance
# doesn't trigger). For subset scenarios, see TODO.c14n/07.
RSpec.describe "C14N xml:* inheritable attributes" do
  let(:ctx) { Moxml.new(:nokogiri) }

  it "renders xml:lang attribute" do
    doc = ctx.parse(%(<root xml:lang="en">hello</root>))
    expect(Moxml::C14n.canonicalize(doc.root))
      .to eq(%(<root xml:lang="en">hello</root>))
  end

  it "renders xml:space attribute" do
    doc = ctx.parse(%(<root xml:space="preserve">data</root>))
    expect(Moxml::C14n.canonicalize(doc.root))
      .to eq(%(<root xml:space="preserve">data</root>))
  end

  it "renders xml:lang on descendant that declares its own" do
    doc = ctx.parse(%(<a xml:lang="en"><b xml:lang="fr"/></a>))
    result = Moxml::C14n.canonicalize(doc.root)
    expect(result).to include('<b xml:lang="fr">')
  end

  it "renders xml:id attribute" do
    doc = ctx.parse(%(<root xml:id="foo"/>))
    expect(Moxml::C14n.canonicalize(doc.root))
      .to eq(%(<root xml:id="foo"></root>))
  end

  it "renders xml:base attribute" do
    doc = ctx.parse(%(<root xml:base="http://example.com/"/>))
    expect(Moxml::C14n.canonicalize(doc.root))
      .to eq(%(<root xml:base="http://example.com/"></root>))
  end

  it "sorts xml:* attributes by namespace URI then local name" do
    doc = ctx.parse(%(<root xml:space="default" xml:lang="en" xml:id="x"/>))
    result = Moxml::C14n.canonicalize(doc.root)
    # All in XML namespace; sort by local name: id < lang < space
    expect(result.index("xml:id=")).to be < result.index("xml:lang=")
    expect(result.index("xml:lang=")).to be < result.index("xml:space=")
  end
end
