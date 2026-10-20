# frozen_string_literal: true

require "spec_helper"

# Citation hygiene (TODO.sota/07): a spec or doc that calls a
# divergence "pre-existing" or "documented" must resolve it to a
# register ID (D-NN) on the same line. The register is the only place
# such a claim is allowed to stand on its own.
CITATION_PHRASE = /(?:\bpre-existing\b|\bpreexisting\b|\bdocumented (?:divergence|limitation)\b)/i

RSpec.describe "divergence citations" do
  def offenses(paths)
    paths.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, idx|
        next unless line.match?(CITATION_PHRASE)
        next if line.match?(/D-\d+/)

        "#{path}:#{idx + 1}: #{line.strip}"
      end
    end
  end

  it "resolves every pre-existing/documented divergence claim to a register ID" do
    paths = (Dir.glob("spec/**/*.rb") + Dir.glob("docs/**/*.adoc"))
      .reject { |path| path.end_with?("citation_hygiene_spec.rb") }
    found = offenses(paths)
    expect(found).to be_empty,
                     "name a D-NN (docs/_pages/divergences.adoc) or drop " \
                     "the claim:\n#{found.join("\n")}"
  end
end
