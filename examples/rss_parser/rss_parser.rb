#!/usr/bin/env ruby
# frozen_string_literal: true

# RSS Feed Parser Example
# This example demonstrates how to use Moxml to parse RSS feeds with:
# - XPath queries for data extraction
# - Namespace handling (dc, content, atom)
# - Element traversal and attribute access
# - Error handling best practices

# Load moxml from the local source (use 'require "moxml"' in production)
require_relative "../../lib/moxml"

# Article class to represent a parsed RSS item
class Article
  attr_reader :title, :link, :description, :content, :author, :pub_date,
              :categories

  def initialize(title:, link:, description:, content: nil, author: nil,
pub_date: nil, categories: [])
    @title = title
    @link = link
    @description = description
    @content = content
    @author = author
    @pub_date = pub_date
    @categories = categories
  end

  def to_s
    output = []
    output << ("=" * 80)
    output << "Title: #{@title}"
    output << "Link: #{@link}"
    output << "Author: #{@author}" if @author
    output << "Published: #{@pub_date}" if @pub_date
    output << "Categories: #{@categories.join(', ')}" unless @categories.empty?
    output << ("-" * 80)
    output << "Description: #{@description}"
    output << ""
    output << "Full Content:" if @content
    output << @content if @content
    output << ("=" * 80)
    output.join("\n")
  end
end

# RSSParser class encapsulates RSS feed parsing logic
class RSSParser
  # Initialize with the path to an RSS feed file
  def initialize(feed_path)
    @feed_path = feed_path
    @moxml = Moxml.new
  end

  # Parse the RSS feed and return an array of Article objects
  def parse
    # Read and parse the XML file
    xml_content = File.read(@feed_path)

    # Parse with error handling
    doc = begin
      @moxml.parse(xml_content)
    rescue Moxml::ParseError => e
      puts "Failed to parse RSS feed: #{e.message}"
      puts "Hint: #{e.hint}" if e.respond_to?(:hint)
      exit 1
    end

    # Define namespace prefixes for XPath queries
    # RSS feeds often use Dublin Core (dc) and Content (content) namespaces
    namespaces = {
      "dc" => "http://purl.org/dc/elements/1.1/",
      "content" => "http://purl.org/rss/1.0/modules/content/",
      "atom" => "http://www.w3.org/2005/Atom",
    }

    # Extract feed metadata using XPath
    feed_title = extract_text(doc, "//channel/title")
    feed_link = extract_text(doc, "//channel/link")
    feed_description = extract_text(doc, "//channel/description")

    puts "Feed: #{feed_title}"
    puts "URL: #{feed_link}"
    puts "Description: #{feed_description}"
    puts "\nArticles:\n\n"

    # Find all item elements using XPath
    # The double slash (//) searches at any depth in the document
    items = begin
      doc.xpath("//item")
    rescue Moxml::XPathError => e
      puts "XPath query failed: #{e.message}"
      puts "Expression: #{e.expression}" if e.respond_to?(:expression)
      exit 1
    end

    # Parse each item into an Article object
    items.map do |item|
      parse_item(item, namespaces)
    end
  end

  private

  # Parse a single RSS item element
  def parse_item(item, namespaces)
    # Extract basic RSS fields
    # Using at_xpath to get the first matching element (returns nil if not found)
    title = extract_text(item, "./title")
    link = extract_text(item, "./link")
    description = extract_text(item, "./description")
    pub_date = extract_text(item, "./pubDate")

    # Extract namespaced elements
    # The dc:creator element uses the Dublin Core namespace
    author = extract_text(item, "./dc:creator", namespaces)

    # Extract CDATA content from the content:encoded element
    # CDATA sections preserve HTML/XML markup without parsing it
    content_node = item.at_xpath("./content:encoded", namespaces)
    content = content_node&.text&.strip

    # Extract all category elements
    # xpath returns a NodeSet which we can iterate over
    category_nodes = item.xpath("./category")
    categories = category_nodes.map(&:text)

    # Create and return Article object
    Article.new(
      title: title,
      link: link,
      description: description,
      content: content,
      author: author,
      pub_date: pub_date,
      categories: categories,
    )
  end

  # Helper method to extract text content from an XPath query
  # Returns empty string if element not found
  def extract_text(node, xpath, namespaces = {})
    element = node.at_xpath(xpath, namespaces)
    element&.text&.strip || ""
  end
end

# Main execution
if __FILE__ == $0
  # Get the feed path (use example feed by default)
  feed_path = ARGV[0] || File.join(__dir__, "example_feed.xml")

  # Check if file exists
  unless File.exist?(feed_path)
    puts "Error: Feed file not found: #{feed_path}"
    puts "Usage: ruby rss_parser.rb [path/to/feed.xml]"
    exit 1
  end

  puts "Parsing RSS feed: #{feed_path}"
  puts "=" * 80
  puts

  # Parse the feed
  parser = RSSParser.new(feed_path)
  articles = parser.parse

  # Display each article
  articles.each_with_index do |article, index|
    puts "\n#{index + 1}. #{article}\n"
  end

  # Summary statistics
  puts "\n#{'=' * 80}"
  puts "Summary:"
  puts "Total articles: #{articles.length}"
  puts "Authors: #{articles.filter_map(&:author).uniq.join(', ')}"

  # Count categories
  all_categories = articles.flat_map(&:categories)
  category_counts = all_categories.each_with_object(Hash.new(0)) do |cat, counts|
    counts[cat] += 1
  end
  puts "Categories: #{category_counts.map do |cat, count|
    "#{cat} (#{count})"
  end.join(', ')}"
  puts "=" * 80
end
