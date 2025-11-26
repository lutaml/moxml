# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in moxml.gemspec
gemspec

gem "byebug"
gem "get_process_mem"
gem "nokogiri", "~> 1.18"
gem "oga", "~> 3.4"
gem "ox", "~> 2.14"
gem "rake"
gem "rexml"
gem "rspec"
gem "rubocop"
gem "rubocop-performance"
gem "rubocop-rake"
gem "rubocop-rspec"
gem "simplecov", require: false
gem "tempfile"
#  Provides iteration per second benchmarking for Ruby
gem "benchmark-ips"

# Needed by get_process_mem on Windows
gem "sys-proctable" if Gem.win_platform?

if Gem.win_platform?
  gem "libxml-ruby", "5.0.4", platforms: :ruby
else
  gem "libxml-ruby"
end
