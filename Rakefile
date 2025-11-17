# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

namespace :benchmark do
  desc "Run XPath performance benchmarks"
  task :xpath do
    ENV.delete("SKIP_BENCHMARKS")
    sh "bundle exec rspec spec/moxml/examples/xpath_benchmark_spec.rb"
  end

  desc "Generate adapter benchmark report"
  task :report do
    ruby "benchmarks/generate_report.rb"
  end
end

task default: %i[spec rubocop]
