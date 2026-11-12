# frozen_string_literal: true

require "spec_helper"

# moxml#540: attribute values decode character references exactly as
# element text does (XML 1.0 §4.6). The leptris adapter's bulk packet
# face served the engine's raw attribute slice — entity runs stayed
# literal on #attributes while #text and the named getters decoded.
# The re-serve through the decoding packet face closes it; this spec
# pins the committed answer on every adapter so no adapter can serve
# a raw reference again.
RSpec.describe "attribute values decode character references" do
  let(:xml) do
    '<x a="&#x2190;" b="p&amp;q" c="&#8592;" d="plain" e="&#9;"/>'
  end

  let(:expected) do
    {
      "a" => "←",
      "b" => "p&q",
      "c" => "←",
      "d" => "plain",
      "e" => "\t",
    }
  end

  it "decodes hex, decimal, and named references identically to text" do
    Moxml::Adapter::AVAILABLE_ADAPTERS.each do |name|
      begin
        ctx = Moxml.new(name)
        root = ctx.parse(xml).root
      rescue Moxml::Error, NotImplementedError, LoadError
        next
      end

      got = root.attributes.to_h { |a| [a.name, a.value] }
      expect(got).to eq(expected),
                     "#{name}: #{got.inspect}"
    end
  end

  it "matches the element-text decode on the same document" do
    ctx = Moxml.new(:leptris)
    doc = ctx.parse('<x a="&#x2190;">&#x2190;</x>')
    expect(doc.root.attributes.first.value).to eq(doc.root.text)
  end

  it "keeps the attribute_pairs bulk face consistent with #attributes" do
    ctx = Moxml.new(:leptris)
    root = ctx.parse(xml).root
    pairs = Moxml::Adapter.load(:leptris).attribute_pairs(root.native)
    got = pairs.to_h { |qualified, value| [qualified, value] }
    expect(got.values_at("a", "b", "c", "d", "e"))
      .to eq(expected.values)
  end
end
