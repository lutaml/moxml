#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "moxml"

xml = File.read(File.join(__dir__, "example.xml"))

puts "=== Example 1: Class-Based Handler ==="
puts

# Define a simple handler class
class SimpleHandler < Moxml::SAX::Handler
  def on_start_document
    puts "Document started"
  end

  def on_start_element(name, attributes = {}, _namespaces = {})
    attrs_str = attributes.map { |k, v| "#{k}=#{v}" }.join(", ")
    puts "  Start element: #{name}" + (attrs_str.empty? ? "" : " [#{attrs_str}]")
  end

  def on_characters(text)
    text = text.strip
    puts "    Text: #{text}" unless text.empty?
  end

  def on_end_element(name)
    puts "  End element: #{name}"
  end

  def on_end_document
    puts "Document ended"
  end
end

context = Moxml.new(:nokogiri)
handler = SimpleHandler.new
context.sax_parse(xml, handler)

puts
puts "=== Example 2: Block-Based Handler ==="
puts

element_count = 0
context.sax_parse(xml) do
  start_document { puts "Document started" }

  start_element do |name, _attrs|
    element_count += 1
    puts "  Element #{element_count}: #{name}"
  end

  end_document { puts "Document ended - processed #{element_count} elements" }
end
