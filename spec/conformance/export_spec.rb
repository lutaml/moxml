# frozen_string_literal: true

require "spec_helper"
require "json"
require "moxml"
require_relative "../../spec/support/conformance_cases"

# #496: the exported fixture is the cross-language conformance
# contract — moxml-rs and moxml-ts runners read the committed JSON, so
# it must never drift from the Ruby pins. This gate re-derives the
# export and fails on any difference, and holds the data to its own
# contract (unique ids, real source pins).
RSpec.describe "conformance fixture export" do
  let(:fixture_path) do
    File.expand_path("../../fixtures/conformance/moxml-conformance.json", __dir__)
  end

  let(:fresh_export) do
    {
      format: 1,
      generator: "rake conformance:export",
      moxml_version: Moxml::VERSION,
      coverage_contract: "runners must answer every case in every face",
      faces: ConformanceCases.faces.transform_values do |face|
        face.merge(case_count: face[:cases].size)
      end,
    }
  end

  it "matches a fresh export of the Ruby pins exactly" do
    committed = JSON.parse(File.read(fixture_path))

    expect(committed).to eq(JSON.parse(JSON.generate(fresh_export)))
  end

  it "gives every case a unique id inside its face" do
    ConformanceCases.faces.each do |face, data|
      ids = data[:cases].map { |c| c[:id] }

      expect(ids.uniq.size).to eq(ids.size),
                               "#{face} has duplicate case ids"
    end
  end

  it "pins every face to a source spec that exists" do
    ConformanceCases.faces.each do |face, data|
      pin = File.expand_path("../../#{data[:source_pin]}", __dir__)

      expect(File).to exist(pin), "#{face}: source pin #{data[:source_pin]} missing"
    end
  end
end
