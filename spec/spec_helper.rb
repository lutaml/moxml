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
require "byebug"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

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

  config.order = :random
  Kernel.srand config.seed
end

Moxml.configure do |config|
  config.adapter = :nokogiri
  config.strict_parsing = true
  config.default_encoding = "UTF-8"
end
