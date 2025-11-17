#!/usr/bin/env ruby
# frozen_string_literal: true

# Web Scraper Example
# This example demonstrates how to use Moxml to scrape data from HTML/XML:
# - Parsing HTML as XML
# - Extracting data from tables
# - DOM structure navigation
# - Attribute and text content access
# - Working with structured data

# Load moxml from the local source (use 'require "moxml"' in production)
require_relative "../../lib/moxml"

# Language class to represent programming language data
class Language
  attr_reader :rank, :name, :category, :score, :year, :use_cases

  def initialize(rank:, name:, category:, score:, year:, use_cases:)
    @rank = rank.to_i
    @name = name
    @category = category
    @score = score.to_f
    @year = year.to_i
    @use_cases = use_cases
  end

  def to_s
    "#{@rank}. #{@name} (#{@category}) - #{@score}% | Created: #{@year} | Uses: #{@use_cases}"
  end
end

# CategoryStats class to represent category statistics
class CategoryStats
  attr_reader :name, :count, :avg_score, :top_language

  def initialize(name:, count:, avg_score:, top_language:)
    @name = name
    @count = count.to_i
    @avg_score = avg_score
    @top_language = top_language
  end

  def to_s
    "#{@name}: #{@count} languages, avg #{@avg_score}, top: #{@top_language}"
  end
end

# WebScraper class encapsulates web scraping logic
class WebScraper
  # Initialize with the path to an HTML file
  def initialize(html_path)
    @html_path = html_path
    @moxml = Moxml.new
  end

  # Scrape the HTML page and extract all data
  def scrape
    # Read and parse the HTML file
    html_content = File.read(@html_path)

    # Parse HTML as XML (Moxml can handle well-formed HTML)
    doc = begin
      @moxml.parse(html_content)
    rescue Moxml::ParseError => e
      puts "Failed to parse HTML: #{e.message}"
      puts "Hint: Ensure the HTML is well-formed XML"
      exit 1
    end

    puts "=" * 80
    puts "Programming Language Statistics Scraper"
    puts "=" * 80
    puts

    # Extract page title
    title = extract_page_title(doc)
    puts "Page Title: #{title}\n\n"

    # Extract summary information
    summary = extract_summary(doc)
    puts "Summary:"
    puts "  #{summary[:total]} total languages tracked"
    puts "  Last updated: #{summary[:updated]}\n\n"

    # Extract language data from the main table
    languages = extract_languages_table(doc)
    puts "Languages Extracted: #{languages.length}"
    puts "-" * 80
    languages.each { |lang| puts lang }
    puts

    # Extract category statistics
    categories = extract_category_stats(doc)
    puts "\nCategory Statistics:"
    puts "-" * 80
    categories.each { |cat| puts cat }
    puts

    # Extract detailed information
    details = extract_detailed_info(doc)
    puts "\nDetailed Information:"
    puts "-" * 80
    details.each do |lang, info|
      puts "#{lang}:"
      info.each { |key, value| puts "  #{key}: #{value}" }
      puts
    end

    # Return structured data
    {
      title: title,
      summary: summary,
      languages: languages,
      categories: categories,
      details: details,
    }
  end

  private

  # Extract the page title from <title> element
  def extract_page_title(doc)
    # Find the title element using XPath
    # The double slash (//) searches from the root
    title_element = doc.at_xpath("//title")
    title_element&.text&.strip || "Unknown Title"
  end

  # Extract summary statistics from the summary card
  def extract_summary(doc)
    # Find the summary div by id attribute
    # XPath attribute selector: [@id='value']
    summary_div = doc.at_xpath("//div[@id='summary']")

    return { total: 0, updated: "Unknown" } unless summary_div

    # Extract text from span elements with class 'stat-value'
    # Using XPath class selector: [contains(@class, 'value')]
    stats = summary_div.xpath(".//span[@class='stat-value']")

    {
      total: stats[0]&.text&.strip || "0",
      updated: stats[1]&.text&.strip || "Unknown",
    }
  end

  # Extract language data from the popularity table
  def extract_languages_table(doc)
    # Find the table by id
    table = doc.at_xpath("//table[@id='popularity-table']")
    return [] unless table

    # Get all table body rows
    # Using descendant axis to find tbody/tr elements
    rows = table.xpath(".//tbody/tr")

    # Parse each row into a Language object
    rows.filter_map do |row|
      # Get all td (cell) elements in this row
      cells = row.xpath("./td")

      # Skip if we don't have enough cells
      next nil if cells.length < 6

      # Extract data from each cell
      # Using array indexing for predictable table structure
      rank = cells[0].text.strip
      name = cells[1].text.strip
      category = cells[2].text.strip

      # Access data-score attribute for the score
      # Demonstrates attribute access with []
      score = cells[3]["data-score"] || cells[3].text.strip.delete("%")

      year = cells[4].text.strip
      use_cases = cells[5].text.strip

      Language.new(
        rank: rank,
        name: name,
        category: category,
        score: score,
        year: year,
        use_cases: use_cases,
      )
    end
  end

  # Extract category statistics from the category table
  def extract_category_stats(doc)
    # Find the category table
    table = doc.at_xpath("//table[@id='category-table']")
    return [] unless table

    # Get table rows
    rows = table.xpath(".//tbody/tr")

    rows.filter_map do |row|
      cells = row.xpath("./td")
      next nil if cells.length < 4

      CategoryStats.new(
        name: cells[0].text.strip,
        count: cells[1].text.strip,
        avg_score: cells[2].text.strip,
        top_language: cells[3].text.strip,
      )
    end
  end

  # Extract detailed language information from stats cards
  def extract_detailed_info(doc)
    # Find all divs with class 'stats-card' that have a data-language attribute
    # This demonstrates combining class and attribute selectors
    cards = doc.xpath("//div[contains(@class, 'stats-card') and @data-language]")

    cards.each_with_object({}) do |card, hash|
      # Get the language name from the data-language attribute
      lang_name = card["data-language"]

      # Extract all list items within this card
      items = card.xpath(".//li")

      # Parse each list item to extract key-value pairs
      info = items.each_with_object({}) do |item, item_hash|
        text = item.text.strip
        # Simple parsing: split on first colon
        if text.include?(":")
          key, value = text.split(":", 2)
          item_hash[key.strip] = value.strip
        end
      end

      hash[lang_name] = info unless info.empty?
    end
  end
end

# Demonstration of various XPath patterns
def demonstrate_xpath_patterns(doc)
  puts "\n#{'=' * 80}"
  puts "XPath Pattern Demonstrations"
  puts "=" * 80

  # Pattern 1: Direct descendant
  puts "\n1. All table headers (//th):"
  headers = doc.xpath("//th")
  puts "   Found #{headers.length} headers: #{headers.map(&:text).join(', ')}"

  # Pattern 2: Attribute selector
  puts "\n2. Elements with data-language attribute (//tr[@data-language]):"
  lang_rows = doc.xpath("//tr[@data-language]")
  langs = lang_rows.map { |row| row["data-language"] }
  puts "   Found #{langs.length} languages: #{langs.join(', ')}"

  # Pattern 3: Class contains
  puts "\n3. Elements with 'language-name' class:"
  names = doc.xpath("//*[contains(@class, 'language-name')]")
  puts "   Found #{names.length} elements: #{names.map(&:text).join(', ')}"

  # Pattern 4: Combining conditions
  puts "\n4. Table cells with data-score > 80:"
  high_scores = doc.xpath("//td[@data-score]").select do |cell|
    cell["data-score"].to_f > 80
  end
  puts "   Found #{high_scores.length} high scores"

  # Pattern 5: Navigation axes
  puts "\n5. Parent elements of language names:"
  first_name = doc.at_xpath("//td[@class='language-name']")
  if first_name
    parent_row = first_name.parent
    puts "   Parent tag: #{parent_row.name}"
    puts "   Parent has #{parent_row.children.length} children"
  end

  puts "=" * 80
end

# Main execution
if __FILE__ == $0
  # Get the HTML path (use example page by default)
  html_path = ARGV[0] || File.join(__dir__, "example_page.html")

  # Check if file exists
  unless File.exist?(html_path)
    puts "Error: HTML file not found: #{html_path}"
    puts "Usage: ruby web_scraper.rb [path/to/page.html]"
    exit 1
  end

  puts "Scraping HTML page: #{html_path}\n"

  # Scrape the page
  scraper = WebScraper.new(html_path)
  data = scraper.scrape

  # Demonstrate various XPath patterns
  doc = Moxml.new.parse(File.read(html_path))
  demonstrate_xpath_patterns(doc)

  # Summary
  puts "\n#{'=' * 80}"
  puts "Scraping Complete!"
  puts "=" * 80
  puts "Extracted:"
  puts "  - #{data[:languages].length} programming languages"
  puts "  - #{data[:categories].length} category statistics"
  puts "  - #{data[:details].length} detailed information entries"
  puts "=" * 80
end
