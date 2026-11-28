# frozen_string_literal: true

require "spec_helper"

# lutaml/moxml#606: under entity-reference retention, parsing
# marker-bearing text mints CustomizedLeptris::TextSegment value
# objects as the native children behind Wrappers::Text. Re-attaching
# such a parsed child via add_child crashed - the attach path handed
# the raw value object to the binding, which accepts only native
# Nodes and Strings. The adapter's own parse output must be accepted
# by its own attach path: a TextSegment attaches as its text content.
RSpec.describe "TextSegment attach under entity retention (#606)" do
  let(:ctx) { Moxml.new(:leptris) }

  before do
    ctx.config.restore_entities = true
  end

  it "re-attaches parsed marker-split children to another element" do
    parsed = ctx.parse(
      "<fragment>alpha&nbsp;beta&mdash;gamma<child a=\"1\"/></fragment>",
    )
    target = parsed.document.create_element("t")

    parsed.root.children.each { |c| target.add_child(c) }

    names = target.children.map { |c| c.respond_to?(:name) ? c.name : nil }
    expect(names).to include("child")
    expect(target.children.count).to be_positive
  end

  it "preserves the re-attached text runs verbatim" do
    parsed = ctx.parse("<fragment>alpha&nbsp;beta&mdash;gamma</fragment>")
    target = parsed.document.create_element("t")

    parsed.root.children.each { |c| target.add_child(c) }

    combined = target.children.to_a.join
    expect(combined).to include("alpha")
    expect(combined).to include("beta")
    expect(combined).to include("gamma")
  end
end
