# frozen_string_literal: true

require "bundler/gem_tasks"

# vendor:prepare must be runnable before `bundle install` (CI runs it
# first so the path-source oga/ruby-ll forks' gitignored lexer/parser
# outputs exist before their extconf.rb runs). Guard the rspec/opal
# requires so the file loads with only `rake` + `bundler` available.
begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
end

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

    # The Opal-compatible oga and ruby-ll forks (vendored as submodules)
    # expose pure-Ruby implementations under ext/pureruby/. Their top-level
    # lib/oga.rb and lib/ll/setup.rb conditionally require them when
    # RUBY_PLATFORM == 'opal'. Both lib/ and ext/pureruby/ must be on
    # Opal's load path so the conditional resolves correctly.
    %w[opal-oga opal-ruby-ll].each do |fork_name|
      fork_path = File.expand_path("vendor/#{fork_name}", __dir__)
      Opal.append_path File.join(fork_path, "lib")
      Opal.append_path File.join(fork_path, "ext/pureruby")
    end
  end
rescue LoadError
  # Opal not available or incompatible with current Ruby version
end

begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new
rescue LoadError
end

# Regenerate the ragel / ruby-ll outputs that the Opal-compatible forks
# (vendored as submodules under vendor/) gitignore. The forks ship the
# grammar sources (.rl / .rll) but not the generated .rb / .c, since
# those are large and version-controllable upstream. Both ragel and
# ruby-ll must be on PATH; the upstream ruby-ll gem is sufficient for
# generation (the fork is only needed at runtime).
namespace :vendor do
  desc "Generate ragel / ruby-ll outputs in vendored opal-oga and opal-ruby-ll"
  task :prepare do
    require "fileutils"

    oga = File.expand_path("vendor/opal-oga", __dir__)
    ruby_ll = File.expand_path("vendor/opal-ruby-ll", __dir__)

    generators = [
      # oga: ruby-ll grammar → Ruby parser
      ["ruby-ll #{oga}/lib/oga/xml/parser.rll -o #{oga}/lib/oga/xml/parser.rb",
       "#{oga}/lib/oga/xml/parser.rb",
       "#{oga}/lib/oga/xml/parser.rll"],
      ["ruby-ll #{oga}/lib/oga/xpath/parser.rll -o #{oga}/lib/oga/xpath/parser.rb",
       "#{oga}/lib/oga/xpath/parser.rb",
       "#{oga}/lib/oga/xpath/parser.rll"],
      ["ruby-ll #{oga}/lib/oga/css/parser.rll -o #{oga}/lib/oga/css/parser.rb",
       "#{oga}/lib/oga/css/parser.rb",
       "#{oga}/lib/oga/css/parser.rll"],
      # oga: ragel Ruby lexer
      ["ragel -R -F1 #{oga}/lib/oga/xpath/lexer.rl -o #{oga}/lib/oga/xpath/lexer.rb",
       "#{oga}/lib/oga/xpath/lexer.rb",
       "#{oga}/lib/oga/xpath/lexer.rl"],
      ["ragel -R -F1 #{oga}/lib/oga/css/lexer.rl -o #{oga}/lib/oga/css/lexer.rb",
       "#{oga}/lib/oga/css/lexer.rb",
       "#{oga}/lib/oga/css/lexer.rl"],
      # oga: ragel C lexer for liboga
      ["ragel -C -I #{oga}/ext/ragel -G2 #{oga}/ext/c/lexer.rl -o #{oga}/ext/c/lexer.c",
       "#{oga}/ext/c/lexer.c",
       "#{oga}/ext/c/lexer.rl"],
      # ruby-ll: ruby-ll grammar → Ruby parser
      ["ruby-ll #{ruby_ll}/lib/ll/parser.rll -o #{ruby_ll}/lib/ll/parser.rb --no-requires",
       "#{ruby_ll}/lib/ll/parser.rb",
       "#{ruby_ll}/lib/ll/parser.rll"],
    ]

    generators.each do |cmd, output, source|
      if File.exist?(output) && File.mtime(output) >= File.mtime(source)
        next
      end

      FileUtils.mkdir_p(File.dirname(output))
      sh cmd
    end
  end
end

namespace :spec do
  if defined?(Opal::RSpec::RakeTask)
    desc "Run Opal (JavaScript) tests"
    Opal::RSpec::RakeTask.new(:opal) do |server, runner|
      server.append_path "lib"
      server.append_path "spec"

      runner.default_path = "spec"
      # `oga` and `ll/setup` must be required before moxml_boot so that
      # the forks' Opal-aware conditional requires fire (lib/oga.rb calls
      # `require 'oga/native/lexer'` when RUBY_PLATFORM == 'opal'; that
      # resolves against vendor/opal-oga/ext/pureruby/, which the global
      # Opal.append_path calls above add to the load path).
      runner.requires = %w[rexml_compat rexml/document rexml/xpath
                           oga ll/setup
                           moxml_boot spec_helper support/opal]
      runner.files = Dir.glob("spec/moxml/*opal*_spec.rb") +
        Dir.glob("spec/moxml/native_attachment/opal_spec.rb") +
        Dir.glob("spec/moxml/adapter/shared_examples/*.rb")
    end

    task :opal => "vendor:prepare"
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
