# frozen_string_literal: true

require "json"
require "spec_helper"

# The serialization conformance family (#490 item 8, family 5): the
# committed element-level serialization answers — the rows are the
# model, exported to conformance/moxml-conformance.json (schema 4)
# for the cross-language runners. Every row round-trips idempotently
# on both primary engines (parse -> serialize twice, byte equality).
#
# Cross-adapter note (D-25): oga, rexml, ox, headed_ox and libxml
# emit a literal newline for a `&#10;` character reference in an
# attribute value; the committed answer is the round-trip-preserving
# escaped form (nokogiri, leptris), since a literal newline
# normalizes to space on the next parse. The family pins the primary
# adapters; the differential's per-adapter rows follow the register.
RSpec.describe "serialization conformance family (schema 4)" do
  let(:primary) { %i[nokogiri leptris] }

  Moxml::SerializationCases::CONFORMANCE_CASES.each do |id, input, output|
    it "serializes #{id} to the committed answer" do
      primary.each do |name|
        doc = Moxml.new(name).parse(input)
        expect(doc.root.to_xml(indent: 0)).to eq(output)
      end
    end
  end

  it "is exported by the dataset with the committed rows" do
    path = File.expand_path("../../conformance/moxml-conformance.json",
                            __dir__)
    dataset = JSON.parse(File.read(path))
    family = dataset.dig("cases", "serialization") || []
    expect(family.size).to eq(
      Moxml::SerializationCases::CONFORMANCE_CASES.size,
    )
    expect(family.map { |row| row["id"] })
      .to eq(Moxml::SerializationCases::CONFORMANCE_CASES.map(&:first))
  end
end
