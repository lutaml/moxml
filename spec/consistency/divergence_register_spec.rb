# frozen_string_literal: true

require "spec_helper"

# Divergence register linkage (TODO.model/02): the register
# (docs/_pages/divergences.adoc) and the consistency suite must stay
# mechanically consistent — every capability-related skip cites a
# register ID, every register entry is cited by at least one spec, and
# no spec cites an unregistered ID.
RSpec.describe "divergence register linkage" do
  REGISTER_PATH = "docs/_pages/divergences.adoc" # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration
  SCAN_GLOBS = %w[spec/consistency/**/*.rb spec/moxml/**/*.rb spec/support/*.rb].freeze # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration
  NEXT_GATE = [ # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration
    /same engine as/, # engine dedup, not a divergence
    /source_adapter == target_adapter/, # self round-trip
    /MAX_SIZE/, # size guard
    /AVAILABLE_ADAPTERS\.include/, # availability filter
    /skip_shapes/,              # shape routing (IDs cited above)
    /leptris_fixed\?/,          # version gate
    /source_elements/,          # data-presence guard
    /next unless doc/,          # adapter-availability guard (not a
    # divergence: the adapter is not installed in this environment)
    /next unless cell\[:pin\]/, # matrix data-presence guard
    /next unless match/,        # scanner-internal guard
    /well_formed|voids\.empty\?|default_ns|per\.size/, # property-scope
    # and availability guards (input scoping, not adapter exemptions)
    /exempt/i, # value-routed exemption table: the
    # table's VALUES are D-IDs, enforced by
    # the coverage audit's exempt rule
  ].freeze

  # Version/availability gates are not divergences: a binding too old
  # or an adapter not installed is a deployment fact, not an
  # engine-vs-model difference at equal versions.
  GATE = [ # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration
    /unavailable/i, /not available/, /predates/, /not installed/i,
    /not present/i, /requires/i, /required\z/, /has no \S+ face/,
    /lacks the /, /carries /, /degraded below/, /lockstep/i,
    /unreleased/i, /stood down/, /recovered without/,
    /Only \S+ available in CI/i, /adapter-specific/i, /noblanks/,
    /SKIP_ parse flags/, /engine < \d/
  ].freeze

  def register_ids
    File.readlines(REGISTER_PATH)
      .filter_map { |line| line[/\A\|\s*(D-\d+)\s*$/, 1] }
      .uniq
  end

  def spec_files
    SCAN_GLOBS.flat_map { |g| Dir[g] }.uniq
  end

  def cited_ids
    spec_files.flat_map { |path| File.readlines(path) }
      .flat_map { |line| line.scan(/D-\d+/) }
      .uniq
  end

  it "has a register with entries" do
    expect(register_ids).not_to be_empty
  end

  it "requires capability-related skips to cite a register ID" do
    offenders = []
    spec_files.each do |path|
      File.readlines(path).each_with_index do |line, i|
        next unless (msg = line[/skip\s+[&(]?\s*["'](.*?)["']/, 1])

        next if GATE.any? { |re| re.match?(msg) }
        next if msg.match?(/D-\d+/)

        offenders << "#{path}:#{i + 1} #{msg.strip[0, 60]}"
      end
    end
    expect(offenders).to be_empty,
                         "capability skips must cite a divergence-register " \
                         "ID (D-NN): #{offenders.join('; ')}"
  end

  it "requires adapter-exempting next-guards to cite a nearby register ID" do
    offenders = []
    spec_files.each do |path|
      next if path.end_with?("divergence_register_spec.rb")

      lines = File.readlines(path)
      lines.each_with_index do |line, i|
        next unless line.match?(/^\s*next\s+(if|unless)\s/)
        next if NEXT_GATE.any? { |re| re.match?(line) }
        next if line.match?(/D-\d+/)

        context = lines[[i - 4, 0].max...i] + lines[(i + 1)..(i + 4)].to_a
        next if context.any? { |l| l.match?(/D-\d+/) }

        offenders << "#{path}:#{i + 1} #{line.strip[0, 60]}"
      end
    end
    expect(offenders).to be_empty,
                         "adapter-exempting next-guards must cite a " \
                         "divergence-register ID (D-NN) on or above the " \
                         "line: #{offenders.join('; ')}"
  end

  it "cites every register entry from at least one spec" do
    missing = register_ids - cited_ids
    expect(missing).to be_empty,
                       "register entries never cited by a spec: " \
                       "#{missing.join(', ')}"
  end

  it "never cites an unregistered divergence ID" do
    orphans = cited_ids - register_ids
    expect(orphans).to be_empty,
                       "specs cite IDs missing from the register: " \
                       "#{orphans.join(', ')}"
  end
end
