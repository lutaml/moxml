# frozen_string_literal: true

require "moxml"

# moxml#606: the parse-time retention lifecycle mints TextSegment
# value objects as native children; the attach path rejected its own
# parse output. The repro parses under entity retention and re-attaches
# every child to a fresh element — the contract (Node or String) holds
# after the unwrap, and the serialized content carries the same text.
RSpec.describe "TextSegment re-attachment" do
  let(:source) do
    "<fragment>alpha&nbsp;beta&mdash;gamma<child a=\"1\"/></fragment>"
  end

  it "attaches parse-minted children to another element" do
    Moxml.configure { |c| c.restore_entities = true }

    parsed = Moxml.parse(source, adapter: :leptris)
    target = parsed.document.create_element("t")

    expect do
      parsed.root.children.each { |child| target.add_child(child) }
    end.not_to raise_error

    text = target.children.grep(Moxml::Text).map(&:content).join
    expect(text).to include("alpha")
    expect(target.children).not_to be_empty
  ensure
    Moxml.configure { |c| c.restore_entities = false }
  end
end
