# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

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

task default: %i[spec rubocop]
