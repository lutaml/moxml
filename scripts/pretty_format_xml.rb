#!/usr/bin/env ruby
# frozen_string_literal: true

require "nokogiri"

input = ARGV[0] or abort "Usage: #{$0} <input.xml> [output.xml]"
output = ARGV[1] || input

xml = File.read(input)
doc = Nokogiri::XML(xml, &:noblanks)
formatted = doc.to_xml(indent: 2)

File.write(output, formatted)
puts "Written to #{output}"
