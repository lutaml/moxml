# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in moxml.gemspec
gemspec

# base64 is a bundled gem on Ruby 3.4+; the signature module requires
# it (the opal dev deps used to carry it transitively).
gem "base64"
# Provides iteration per second benchmarking for Ruby
gem "benchmark"
gem "benchmark-ips"
gem "get_process_mem"
gem "leptris", "~> 1.9.386"
gem "libxml-ruby", ">= 5.0"
gem "nokogiri", "~> 1.18"
gem "oga"
gem "openssl", "~> 3.0"
gem "ox", "~> 2.14"
gem "rake"
gem "rexml"

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
