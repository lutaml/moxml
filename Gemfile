# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in moxml.gemspec
gemspec

# Provides iteration per second benchmarking for Ruby
gem "benchmark"
gem "benchmark-ips"
gem "get_process_mem"
gem "libxml-ruby", "~> 5.0"
gem "nokogiri", "~> 1.18"
gem "openssl", "~> 3.0"
gem "ox", "~> 2.14"
gem "rake"
gem "rexml"

# Opal-compatible forks of oga and ruby-ll. The forks add pure-Ruby lexer
# and driver fallbacks (under ext/pureruby/) plus an Opal-aware conditional
# in lib/oga.rb / lib/ll/setup.rb that selects the pure-Ruby implementation
# when RUBY_PLATFORM == 'opal'. Under CRuby/JRuby the forks behave
# identically to upstream (the conditional falls through to liboga/libll).
gem "oga", path: "vendor/opal-oga"
gem "ruby-ll", path: "vendor/opal-ruby-ll"

gem "rspec"
gem "rubocop"
gem "rubocop-performance"
gem "rubocop-rake"
gem "rubocop-rspec"
gem "simplecov", require: false
# stackprof relies on POSIX signals (SIGPROF/sigaction) unavailable on Windows
gem "stackprof" unless Gem.win_platform?
gem "tempfile"

# Needed by get_process_mem on Windows
gem "sys-proctable" if Gem.win_platform?

group :opal do
  gem "opal", "~> 1.8"
  gem "opal-rspec", "~> 1.0"
  gem "opal-sprockets"
end
