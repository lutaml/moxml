#!/usr/bin/env ruby

require "rubygems"
# spec = Gem::Specification.find_by_name("libxml-ruby")
spec = Gem::Specification.find_by_name("moxml")
puts spec.full_gem_path

# all_files = Dir.glob("#{spec.full_gem_path}/**/*").select { |f| File.file?(f) }

# all_files.each do |file|
#   puts file
# end

# check PATH
puts ENV.fetch("PATH", nil)

# patch lib/libxml-ruby.rb
# filepath = "a.txt"
filepath = File.expand_path("#{spec.full_gem_path}/dlls")
ENV["PATH"] = "#{ENV.fetch("PATH", nil)};#{filepath}"

puts "Patched PATH:"
puts ENV.fetch("PATH", nil)

# original_content = File.read(filepath)

# line_to_add = "ENV['PATH'] = ENV['PATH'] + ';' + File.expand_path(File.dirname(__FILE__))\nputs 'Patched PATH: ' + ENV['PATH']"

# # Combine the new line with the original content
# new_content = line_to_add + "\n" + original_content

# # Overwrite the file with the new content
# File.write(filepath, new_content)

# puts "new_content================"
# puts new_content
# puts "==========================="

# LD_LIBRARY_PATH
