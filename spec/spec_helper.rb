# frozen_string_literal: true

# SimpleCov must be loaded before application code
if ENV.fetch("COVERAGE", nil) == "true"
  require "simplecov"

  SimpleCov.start do
    add_filter "/spec/"
    add_filter "/vendor/"

    add_group "Core", "lib/moxml/*.rb"
    add_group "Adapters", "lib/moxml/adapter"
    add_group "Utilities", "lib/moxml/xml_utils"

    # Adapter-specific groups
    add_group "Nokogiri Adapter", "lib/moxml/adapter/nokogiri.rb"
    add_group "Oga Adapter", "lib/moxml/adapter/oga.rb"
    add_group "REXML Adapter", "lib/moxml/adapter/rexml.rb"
    add_group "LibXML Adapter", "lib/moxml/adapter/libxml.rb"
    add_group "Ox Adapter", "lib/moxml/adapter/ox.rb"

    minimum_coverage 90
    minimum_coverage_by_file 80
  end
end

require "moxml"
require "nokogiri"

# Load shared examples from new locations
Dir[File.expand_path("integration/shared_examples/**/*.rb",
                     __dir__)].each do |f|
  require f
end
Dir[File.expand_path("moxml/adapter/shared_examples/**/*.rb",
                     __dir__)].each do |f|
  require f
end
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }
Dir[File.expand_path("performance/*.rb", __dir__)].each { |f| require f }
Dir[File.expand_path("examples/*.rb", __dir__)].each { |f| require f }

# Clear XPath caches immediately to ensure fresh compilation
# This is critical when code changes affect compiled XPath expressions
if defined?(Moxml::XPath::Compiler::CACHE)
  Moxml::XPath::Compiler::CACHE.clear
end
if defined?(Moxml::XPath::Parser::CACHE)
  Moxml::XPath::Parser::CACHE.clear
end

# Clear XPath caches before each test to ensure fresh compilation
RSpec.configure do |config|
  config.before do
    Moxml::XPath::Compiler::CACHE.clear if defined?(Moxml::XPath::Compiler::CACHE)
    Moxml::XPath::Parser::CACHE.clear if defined?(Moxml::XPath::Parser::CACHE)
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true

  # Configure to skip performance tests by default
  config.filter_run_excluding performance: true unless ENV["RUN_PERFORMANCE"]

  # Configure to skip examples unless explicitly run
  config.filter_run_excluding examples: true unless ENV["RUN_EXAMPLES"]

  config.order = :random
  Kernel.srand config.seed
end

Moxml.configure do |config|
  config.adapter = :nokogiri
  config.strict_parsing = true
  config.default_encoding = "UTF-8"
end
