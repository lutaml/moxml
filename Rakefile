# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

begin
  require "opal/rspec/rake_task"

  # REXML is a bundled gem since Ruby 3.4; its source must be on Opal's
  # global load path so the compiler can follow `require "rexml/document"`.
  # Opal-compatible overrides go first so they shadow the gem originals.
  if defined?(Opal)
    Opal.append_path File.expand_path("lib/compat/opal", __dir__)
    rexml_lib = $LOAD_PATH.find do |p|
      File.exist?(File.join(p, "rexml", "document.rb"))
    end
    Opal.append_path rexml_lib if rexml_lib
  end
rescue LoadError
  # Opal not available or incompatible with current Ruby version
end

require "rubocop/rake_task"

RuboCop::RakeTask.new

namespace :spec do
  if defined?(Opal::RSpec::RakeTask)
    desc "Run Opal (JavaScript) tests"
    Opal::RSpec::RakeTask.new(:opal) do |server, runner|
      server.append_path "lib"
      server.append_path "spec"

      runner.default_path = "spec"
      runner.requires = %w[rexml_compat rexml/document rexml/xpath
                           moxml/adapter/rexml spec_helper support/opal]
      runner.files = Dir.glob("spec/moxml/*opal*_spec.rb") +
        Dir.glob("spec/moxml/native_attachment/opal_spec.rb") +
        Dir.glob("spec/moxml/adapter/shared_examples/*.rb")
    end
  end

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
    t.pattern = "spec/unit/**/*_spec.rb"
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

  desc "Run performance benchmarks"
  RSpec::Core::RakeTask.new(:performance) do |t|
    t.pattern = "spec/performance/**/*_spec.rb"
    t.rspec_opts = "--tag performance"
  end

  desc "Run unit + adapter + integration (fast feedback)"
  task fast: %i[unit adapter integration]

  desc "Run everything including examples and performance"
  task all: %i[unit adapter integration consistency examples
               performance]
end

namespace :benchmark do
  desc "Run XPath performance benchmarks"
  task :xpath do
    ENV.delete("SKIP_BENCHMARKS")
    sh "bundle exec rspec spec/performance/xpath_benchmark_spec.rb"
  end

  desc "Generate adapter benchmark report"
  task :report do
    ruby "benchmarks/generate_report.rb"
  end
end

namespace :opal do
  desc "Regenerate entity data for Opal from w3c_entities.json"
  task :generate_entity_data do
    require "json"

    source = File.join(__dir__, "data", "w3c_entities.json")
    target = File.join(__dir__, "lib", "moxml", "entity_registry_opal_data.rb")

    data = JSON.parse(File.read(source))
    chars = data["characters"]

    lines = []
    lines << "# frozen_string_literal: true"
    lines << "#"
    lines << "# Auto-generated entity data for Opal runtime."
    lines << "# Source: data/w3c_entities.json (#{chars.size} entities)"
    lines << "# Regenerate with: rake opal:generate_entity_data"
    lines << ""
    lines << "module Moxml"
    lines << "  class EntityRegistry"
    lines << "    OPAL_ENTITY_DATA = {"
    chars.each do |name, char|
      codepoint = if char.start_with?("\\u")
                    char.unicode_normalize(:nfc)[2..].to_i(16)
                  else
                    char.ord
                  end
      lines << "      #{name.inspect} => #{codepoint},"
    end
    lines << "    }.freeze"
    lines << "  end"
    lines << "end"

    File.write(target, "#{lines.join("\n")}\n")
    puts "Generated #{target} (#{chars.size} entities, #{lines.size} lines)"
  end
end

task default: %i[spec rubocop]
