# frozen_string_literal: true

require "spec_helper"
require "support/model_coverage"
require "json"

# Published documentation is part of the specification apparatus
# (TODO.sota/07): generated blocks must be views of committed data. A
# data change without regeneration fails here, so the published
# coverage proof and scoreboard can never claim more than the tests do.
RSpec.describe "published documentation" do
  it "keeps the model-coverage page in sync with the matrix" do
    page = File.read("docs/_pages/model-coverage.adoc")
    block = page[/MODEL-COVERAGE:BEGIN\n(.*?)\n?\/\/ MODEL-COVERAGE:END/m, 1]
    expect(block).not_to be_nil, "coverage page is missing its markers"

    expect(block).to eq(ModelCoverage.render_page_block),
                     "model-coverage page is stale: run rake docs:coverage"
  end

  it "keeps every published scoreboard row in sync with the JSON data" do
    data = JSON.parse(File.read("benchmark/scoreboard.json"))
    page = File.read("docs/_pages/performance.adoc")
    block = page[/SCOREBOARD:BEGIN(.*?)SCOREBOARD:END/m, 1]
    expect(block).not_to be_nil, "performance page is missing its markers"

    data["rows"].each do |row|
      expect(block).to include(
        "| `#{row['row']}` | #{format('%.2f', row['ratio'])}x | " \
        "#{row['kind']} |",
      ), "scoreboard row #{row['row']} is stale against scoreboard.json"
    end

    expect(block.scan(/\| `[^`]+` \| \d+\.\d\dx \|/).size)
      .to eq(data["rows"].size), "scoreboard row count differs"
  end

  it "names the measured engine version in the scoreboard metadata" do
    data = JSON.parse(File.read("benchmark/scoreboard.json"))
    protocol = data["protocol"]
    page = File.read("docs/_pages/performance.adoc")
    block = page[/SCOREBOARD:BEGIN(.*?)SCOREBOARD:END/m, 1]

    expect(block).to include("#{protocol['adapter']} " \
                             "#{protocol['adapter_version']}"),
                     "scoreboard metadata does not name the measured engine"
    expect(block).to include("nokogiri #{protocol['nokogiri']}")
  end
end
