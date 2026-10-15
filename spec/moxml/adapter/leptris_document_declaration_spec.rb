# frozen_string_literal: true

require "spec_helper"

# leptris-ruby#459 exposes the declaration as a Document#children
# entry (binding 1.9.360). The serialize child walk must skip it —
# the composed preamble owns the emission — or declaration-bearing
# round trips duplicate the line (1.9.359) or raise (1.9.360's
# 0-arity Declaration#to_xml under the options-passing call).
RSpec.describe "leptris document declaration child" do
  let(:ctx) { Moxml.new(:leptris) }
  let(:xml) { %(<?xml version="1.0" encoding="UTF-8"?>\n<documents></documents>) }

  before do
    unless Gem::Version.new(Leptris::VERSION) >= Gem::Version.new("1.9.360.0")
      skip "binding #{Leptris::VERSION} predates the declaration child (1.9.360)"
    end
  end

  it "round trips byte-identical with exactly one declaration" do
    doc = ctx.parse(xml)
    out = doc.to_xml

    expect(out).to eq("#{xml}\n")
    expect(out.scan("<?xml").length).to eq(1)
  end

  it "never lists the declaration among document children" do
    doc = ctx.parse(xml)
    first = doc.children.to_a
    second = doc.children.to_a

    expect(first.map(&:node_type)).to eq(%i[element])
    expect(second.map(&:node_type)).to eq(first.map(&:node_type))
    expect(doc.to_xml).to eq("#{xml}\n")
  end

  it "keeps declaration-less documents unchanged" do
    doc = ctx.parse("<r/>")
    expect(doc.to_xml).to eq("<r></r>\n")
  end
end
