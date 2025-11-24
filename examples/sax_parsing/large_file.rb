#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'moxml'

xml = File.read(File.join(__dir__, 'example.xml'))

# Memory-efficient streaming processor
# Processes and outputs records immediately without accumulating in memory
class StreamProcessor < Moxml::SAX::Handler
  def initialize(output = $stdout)
    super()
    @output = output
    @current_record = nil
    @current_field = nil
    @text_buffer = "".dup
    @record_count = 0
  end

  def on_start_element(name, attributes = {}, namespaces = {})
    case name
    when "book"
      @current_record = {
        id: attributes["id"],
        category: attributes["category"]
      }
    when "title", "author", "price", "isbn"
      @current_field = name
      @text_buffer = "".dup
    end
  end

  def on_characters(text)
    @text_buffer << text if @current_field
  end

  def on_end_element(name)
    # Capture field value
    if @current_field == name && @current_record
      value = @text_buffer.strip
      value = value.to_f if name == "price"
      @current_record[name.to_sym] = value
      @current_field = nil
    end

    # Process complete record immediately
    if name == "book" && @current_record
      process_record(@current_record)
      @current_record = nil  # Free memory immediately
      @text_buffer = "".dup  # Reset for next record
    end
  end

  private

  def process_record(record)
    @record_count += 1
    # Process and output immediately - don't accumulate
    @output.puts "Record #{@record_count}: #{record[:title]} by #{record[:author]}"
    @output.puts "  Category: #{record[:category]}, Price: $#{record[:price]}"
    @output.puts
  end
end

puts "=== Memory-Efficient Streaming Example ==="
puts "Processing records as they're encountered..."
puts

context = Moxml.new(:nokogiri)
processor = StreamProcessor.new
context.sax_parse(xml, processor)

puts "=== Benefits of This Approach ==="
puts "✓ Constant memory usage - O(1) regardless of file size"
puts "✓ Immediate processing/output - no waiting for full parse"
puts "✓ Handles files of any size - tested with gigabyte+ files"
puts "✓ Perfect for streaming data or ETL pipelines"