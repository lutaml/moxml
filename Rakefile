# frozen_string_literal: true

require "bundler/gem_tasks"

# Guard the rspec requires so the file loads with only `rake` +
# `bundler` available.
begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
end

begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new
rescue LoadError
end

if defined?(RSpec)
namespace :spec do
  desc "Validate XML fixtures are well-formed (requires xmllint)"
  task :validate_fixtures do
    fixtures = Dir.glob("spec/fixtures/**/*.xml")
    if fixtures.empty?
      abort "No XML fixtures found in spec/fixtures/"
    end

    unless system("which xmllint > /dev/null 2>&1")
      abort "xmllint not found. Install with: brew install libxml2 (macOS) or apt install libxml2-utils (Linux)"
    end

    # Intentionally malformed fixtures (W3C test cases for error handling)
    exemptions = %w[
      spec/fixtures/w3c/namespaces/1.0/035.xml
    ]

    errors = []
    fixtures.each do |path|
      next if exemptions.include?(path)

      output = `xmllint --noout "#{path}" 2>&1`
      errors << "#{path}: #{output.strip}" unless $?.success?
    end

    if errors.empty?
      puts "#{fixtures.size} XML fixtures validated OK"
    else
      abort "Invalid fixtures:\n#{errors.join("\n")}"
    end
  end

  desc "Run unit tests only"
  RSpec::Core::RakeTask.new(:unit) do |t|
    # Unit specs live under spec/moxml/ — the stale glob matched
    # nothing (spec/unit/ holds only the rexml_isolated_test.rb
    # entity-era investigation artifact), so this leg ran zero
    # examples and hid the moxml suite from the fast gate.
    t.pattern = "spec/moxml/**/*_spec.rb"
    t.exclude_pattern = "spec/moxml/adapter/**/*_spec.rb"
  end

  desc "Run adapter tests only"
  RSpec::Core::RakeTask.new(:adapter) do |t|
    t.pattern = "spec/moxml/adapter/**/*_spec.rb"
  end

  desc "Run integration tests only"
  RSpec::Core::RakeTask.new(:integration) do |t|
    t.pattern = "spec/integration/**/*_spec.rb"
  end

  desc "Run consistency tests only"
  RSpec::Core::RakeTask.new(:consistency) do |t|
    t.pattern = "spec/consistency/**/*_spec.rb"
  end

  namespace :consistency do
    desc "Run round-trip tests for a specific fixture category (CATEGORIES=metanorma,rfcxml,niso-jats)"
    task :by_category do
      categories = ENV.fetch("CATEGORIES", "").split(",").map(&:strip)
      abort "Usage: CATEGORIES=metanorma,rfcxml rake spec:consistency:by_category" if categories.empty?

      include_filters = categories.map do |c|
        "--tag fixture_category:#{c}"
      end.join(" ")
      sh "bundle exec rspec spec/consistency/ --tag round_trip #{include_filters}"
    end
  end

  desc "Run example tests"
  RSpec::Core::RakeTask.new(:examples) do |t|
    t.pattern = "spec/examples/**/*_spec.rb"
  end

  desc "Run performance benchmarks (sets RUN_PERFORMANCE=1)"
  RSpec::Core::RakeTask.new(:performance) do |t|
    ENV["RUN_PERFORMANCE"] = "1"
    t.pattern = "spec/performance/**/*_spec.rb"
    t.rspec_opts = "--tag performance"
  end

  desc "Run unit + adapter + integration (fast feedback)"
  task fast: %i[unit adapter integration]

  desc "Run everything including examples and performance"
  task all: %i[unit adapter integration consistency examples
               performance]
end
end

namespace :benchmark do
  desc "Run XPath performance benchmarks"
  task :xpath do
    ENV.delete("SKIP_BENCHMARKS")
    sh "bundle exec rspec spec/performance/xpath_benchmark_spec.rb"
  end
  # Consumer-pipeline leg (issue #198): nested document walked into
  # typed objects — median time + GC.stat allocation deltas, where
  # engine-level numbers hide wrapper overhead. PIPELINE_ADAPTER and
  # PIPELINE_REPS env-overridable.
  desc "Consumer-pipeline benchmark (typed-object walk, issue #198)"
  task :pipeline do
    sh "ruby", "benchmark/pipeline_bench.rb"
  end

  # Plan-bench regression lock (#249 follow-up): Moxml::Plan vs the
  # wrapper walk vs raw nokogiri on the consumer shape. With
  # LEPTRIS_BENCH_LOCK=1 (CI) it exits 1 when plan time exceeds
  # 1.5x raw nokogiri — the "raw-nokogiri CPU parity" regression
  # tripwire.
  desc "Plan materialization benchmark with raw-nokogiri parity lock"
  task :plan do
    sh "bundle exec ruby benchmark/plan_bench.rb"
  end

  # SAX bench row (leptris#1298 / #279): the bulk record drain vs
  # the callback Recorder. With LEPTRIS_BENCH_LOCK=1 (CI) it exits 1
  # unless records-walk allocations stay under half the recorder's.
  desc "SAX parse benchmark: record drain vs callback recorder"
  task :sax do
    sh "bundle exec ruby benchmark/sax_bench.rb"
  end

  desc "Generate adapter benchmark report"
  task :report do
    ruby "benchmarks/generate_report.rb"
  end

  # Published scoreboard (TODO.sota/04): CPU medians, interleaved A/B,
  # load-gated; see benchmark/README.md for the protocol and rows.
  desc "Published performance scoreboard (CPU medians, interleaved A/B)"
  task :scoreboard do
    sh "bundle exec ruby benchmark/scoreboard.rb"
  end

  # CI lock: parity rows must be >= 1.0x and no row may fall more than
  # 10% below the committed baseline. SCORE_JSON rides along so a
  # failed lock still uploads the measurement that failed it — the
  # artifact is the evidence, not the stale committed baseline.
  desc "Scoreboard regression lock (parity + 10% baseline tolerance)"
  task :lock do
    sh({ "SCORE_LOCK" => "1",
         "SCORE_BASELINE" => "benchmark/scoreboard.json",
         "SCORE_JSON" => "/tmp/measured-scoreboard.json" },
       "bundle exec ruby benchmark/scoreboard.rb")
  end
end

namespace :docs do
  desc "Regenerate the published model-coverage page from the matrix"
  task :coverage do
    sh "bundle exec ruby -I spec bin/generate-model-coverage"
  end
end

namespace :conformance do
  desc "Export the cross-language conformance dataset to JSON (#496)"
  task :export do
    require "json"
    require_relative "lib/moxml"
    lexical = Moxml::XSD::BuiltinLexical::CONFORMANCE_CASES
    regex = Moxml::XSD::SchemaRules::XsdRegex::CONFORMANCE_CASES
    wildcards = Moxml::XSD::SchemaRules::Wildcard::WILDCARD_CASES
    entities = Moxml::EntityRegistry::ENTITY_CONFORMANCE_CASES
    payload = {
      schema: 3,
      generator: "moxml #{Moxml::VERSION}",
      cases: {
        "builtin_lexical" => lexical.map do |type, lexical_value, expected|
          { "type" => type, "lexical" => lexical_value, "valid" => expected }
        end,
        "xsd_regex_translation" => regex.map do |pattern, value, matches, translatable|
          {
            "pattern" => pattern, "value" => value,
            "matches" => matches, "translatable" => translatable
          }
        end,
        "schema_wildcards" => wildcards.map do |row|
          constraint, process, not_namespace, not_qname, item_ns, item_qname,
            defined, sibling_names, covers, exclusion = row
          {
            "constraint" => constraint, "process" => process,
            "not_namespace" => not_namespace, "not_qname" => not_qname,
            "item_namespace" => item_ns, "item_qname" => item_qname,
            "defined" => defined, "sibling_names" => sibling_names,
            "covers" => covers, "exclusion" => exclusion
          }
        end,
        "entity_registry" => entities.map do |row|
          seed, qname, qcp, restore_entities, mode, declared, codepoint,
            names, primary, standard, restore = row
          {
            "seed" => seed, "qname" => qname, "qcp" => qcp,
            "restore_entities" => restore_entities, "mode" => mode,
            "declared" => declared, "codepoint" => codepoint,
            "names" => names, "primary" => primary,
            "standard" => standard, "restore" => restore
          }
        end,
      },
    }
    dir = File.expand_path("conformance", __dir__)
    FileUtils.mkdir_p(dir)
    target = File.join(dir, "moxml-conformance.json")
    File.write(target, "#{JSON.pretty_generate(payload)}\n")
    total = lexical.size + regex.size + wildcards.size + entities.size
    puts "conformance: exported #{total} cases to #{target}"
  end
end

task default: :spec
