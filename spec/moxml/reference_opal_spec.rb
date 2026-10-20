# frozen_string_literal: true

require "spec_helper"

# The engine-free lane (TODO.sota/03): the reference is pure Ruby and
# answers the model where no native engine exists. This spec proves it
# transpiles and runs under Opal.
RSpec.describe "Moxml::Reference under Opal", if: RUBY_ENGINE == "opal" do
  it "parses, answers faces, and writes without a native engine" do
    document = Moxml::Reference.parse(
      '<r a="1"><b>t&amp;u</b><![CDATA[c]]><?pi d?></r>',
    )
    expect(Moxml::Reference.element_names(document)).to eq(%w[r b])
    expect(Moxml::Reference.child_element_names(document)).to eq([["b"], []])
    element = document.root.children.find(&:element?)
    expect(element.children.map(&:kind)).to eq([:text])
    expect(element.children.first.data).to eq("t&u")
    expect(document.root.text).to eq("t&uc")
    expect(Moxml::Reference.processing_instructions(document))
      .to eq([["pi", "d"]])
    expect(Moxml::Reference.to_xml(document))
      .to include("<r a=\"1\">", "<b>t&amp;u</b>", "<![CDATA[c]]>")
  end

  it "raises a named ParseError for malformed input" do
    expect { Moxml::Reference.parse("<r><c></r>") }
      .to raise_error(Moxml::ParseError)
  end
end
