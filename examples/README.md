# Moxml Real-World Examples

This directory contains practical, runnable examples demonstrating moxml usage in common real-world scenarios.

## Overview

Each example demonstrates different aspects of moxml's capabilities:

- **RSS Parser**: Parse RSS/Atom feeds with XPath queries and namespace handling
- **Web Scraper**: Extract data from HTML/XML using DOM navigation
- **API Client**: Build and parse XML API requests/responses

## Requirements

All examples require moxml and at least one XML adapter:

```bash
gem install moxml nokogiri
```

## Running the Examples

Each example is self-contained and can be run directly:

```bash
# RSS Parser Example
ruby examples/rss_parser/rss_parser.rb

# Web Scraper Example
ruby examples/web_scraper/web_scraper.rb

# API Client Example
ruby examples/api_client/api_client.rb
```

## Example Details

### RSS Parser (`rss_parser/`)

Demonstrates:
- Parsing RSS/Atom feed XML
- XPath queries for data extraction
- Namespace handling
- Element traversal
- Attribute access

**Files:**
- `rss_parser.rb` - Main parser implementation
- `example_feed.xml` - Sample RSS feed
- `README.md` - Detailed documentation

### Web Scraper (`web_scraper/`)

Demonstrates:
- HTML/XML document parsing
- Table data extraction
- DOM structure navigation
- Attribute and text content access
- Error handling

**Files:**
- `web_scraper.rb` - Main scraper implementation
- `example_page.html` - Sample HTML page
- `README.md` - Detailed documentation

### API Client (`api_client/`)

Demonstrates:
- Building XML API requests
- Parsing XML API responses
- SOAP message handling
- Authentication elements
- Error response processing

**Files:**
- `api_client.rb` - Main client implementation
- `example_response.xml` - Sample API response
- `README.md` - Detailed documentation

## Key Concepts

### Using require_relative

All examples use `require_relative` to load moxml from the local source:

```ruby
require_relative '../../lib/moxml'
```

This allows running the examples directly from the repository without installing the gem.

### Error Handling

Each example includes comprehensive error handling:

```ruby
begin
  doc = Moxml.new.parse(xml)
rescue Moxml::ParseError => e
  puts "Parse error: #{e.message}"
  exit 1
end
```

### Best Practices

The examples demonstrate moxml best practices:
- Proper namespace handling
- Efficient XPath queries
- Clean resource management
- Comprehensive error handling
- Clear, commented code

## Learning Path

1. **Start with RSS Parser** - Learn basic parsing and XPath
2. **Move to Web Scraper** - Understand DOM navigation
3. **Finish with API Client** - Master XML generation and complex structures

## Additional Resources

- [Main README](../README.adoc) - Complete moxml documentation
- [API Reference](../docs/) - Detailed API documentation
- [Guides](../docs/_guides/) - Step-by-step tutorials