# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

namespace :spec do
  desc "Run unit tests only"
  RSpec::Core::RakeTask.new(:unit) do |t|
    t.pattern = "spec/unit/**/*_spec.rb"
  end

  desc "Run adapter tests only"
  RSpec::Core::RakeTask.new(:adapter) do |t|
    t.pattern = "spec/adapter/**/*_spec.rb"
  end

  desc "Run integration tests only"
  RSpec::Core::RakeTask.new(:integration) do |t|
    t.pattern = "spec/integration/**/*_spec.rb"
  end

  desc "Run consistency tests only"
  RSpec::Core::RakeTask.new(:consistency) do |t|
    t.pattern = "spec/consistency/**/*_spec.rb"
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
  task :fast => [:unit, :adapter, :integration]

  desc "Run everything including examples and performance"
  task :all => [:unit, :adapter, :integration, :consistency, :examples, :performance]
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
