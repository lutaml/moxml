#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "moxml"

xml = File.read(File.join(__dir__, "example.xml"))

# Handler that extracts book data using ElementHandler utilities
class BookExtractor < Moxml::SAX::ElementHandler
  attr_reader :books

  def initialize
    super
    @books = []
    @current_book = nil
    @current_field = nil
    @current_text = +""
  end

  def on_start_element(name, attributes = {}, namespaces = {})
    super # Important: updates element stack

    case name
    when "book"
      @current_book = {
        id: attributes["id"],
        category: attributes["category"],
      }
      puts "Found book with ID: #{attributes['id']}"
    when "title", "author", "price", "isbn"
      @current_field = name
      @current_text = +""
    end
  end

  def on_characters(text)
    # Accumulate text - may be called multiple times for one element
    @current_text << text if @current_field
  end

  def on_end_element(name)
    # Process completed elements
    if @current_field == name && @current_book
      value = @current_text.strip
      value = value.to_f if name == "price"
      @current_book[name.to_sym] = value
      puts "  #{name.capitalize}: #{value}"
      @current_field = nil
    end

    if name == "book" && @current_book
      @books << @current_book
      puts "  Complete book added\n\n"
      @current_book = nil
    end

    super # Important: updates element stack
  end
end

puts "=== SAX Data Extraction Example ==="
puts

context = Moxml.new(:nokogiri)
handler = BookExtractor.new
context.sax_parse(xml, handler)

puts "=== Summary ==="
puts "Total books extracted: #{handler.books.size}"
puts
puts "Programming books:"
handler.books.select { |b| b[:category] == "programming" }.each do |book|
  puts "  - #{book[:title]} by #{book[:author]} ($#{book[:price]})"
end
