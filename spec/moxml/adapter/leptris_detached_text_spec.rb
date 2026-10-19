# frozen_string_literal: true

require "spec_helper"

# Issue #401: Text#content= on a detached (parentless) node answered
# the engine's bare "Invalid argument" with no indication of the cause.
# The leptris adapter now re-raises it as a named Moxml error carrying
# the detachment. Created-unattached nodes work (probe), so only the
# failing detachment is re-raised.
RSpec.describe "detached text content= names the cause" do
  let(:ctx) { Moxml.new(:leptris) }

  it "raises a named Moxml error for a removed text node" do
    doc = ctx.parse("<r><a>x</a><b>y</b></r>")
    text = doc.root.children[0].children[0]
    text.remove

    expect { text.content = "z" }
      .to raise_error(Moxml::Error, /detached \(parentless\).*issue #401/)
  end

  it "keeps created-unattached nodes mutable" do
    text = ctx.create_document.create_text("x")
    text.content = "y"
    expect(text.content).to eq("y")
  end

  it "keeps attached nodes mutable" do
    doc = ctx.parse("<r><a>x</a></r>")
    text = doc.root.children[0].children[0]
    text.content = "z"
    expect(text.content).to eq("z")
  end
end
