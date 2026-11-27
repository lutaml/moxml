# frozen_string_literal: true

require "spec_helper"

# lutaml/moxml#584: fragment / multi-root builder mode — several
# sibling top-level elements serializing as standalone concatenated
# markup, no root, no declaration (the metanorma stack's #noko
# shape, 73k calls per compile).
RSpec.describe "Moxml.fragment" do
  let(:ctx) { Moxml.new(:leptris) }

  it "serializes sibling elements concatenated, no root or declaration" do
    builder = Moxml.fragment(:leptris)
    builder.build do
      element("p") { text("a") }
      element("p") { text("b") }
    end

    expect(builder.to_xml).to eq("<p>a</p><p>b</p>")
  end

  it "carries attributes and nesting byte-exactly" do
    builder = Moxml.fragment(:leptris)
    builder.build do
      element("p", id: "1") do
        element("em") { text("deep") }
      end
      text("tail")
    end

    expect(builder.to_xml).to eq(%(<p id="1"><em>deep</em></p>tail))
  end

  it "takes the block at construction" do
    out = Moxml.fragment(:leptris) do
      element("x")
    end

    # the empty-element form is the lane serialization (self-closed
    # comes from the face path only) - the fragment contract is the
    # concatenated structure
    expect(out.to_xml).to eq("<x></x>")
  end

  it "answers empty fragments with an empty string" do
    builder = Moxml.fragment(:leptris)

    expect(builder.to_xml).to eq("")
  end

  it "mixes element and text top-level content (mixed fragment)" do
    builder = Moxml.fragment(:leptris)
    builder.build do
      text("lead")
      element("span") { text("mid") }
    end

    expect(builder.to_xml).to eq("lead<span>mid</span>")
  end
end
