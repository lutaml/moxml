#!/usr/bin/env ruby
# frozen_string_literal: true

require "nokogiri"

input = ARGV[0]
output = ARGV[1] || input

abort "Usage: #{$PROGRAM_NAME} <input.xml> [output.xml]" unless input
abort "File not found: #{input}" unless File.exist?(input)

doc = Nokogiri::XML(File.read(input), &:noblanks)
formatted = doc.to_xml(indent: 2)

File.write(output, formatted)
puts "Formatted #{input}#{" -> #{output}" if output != input}"
