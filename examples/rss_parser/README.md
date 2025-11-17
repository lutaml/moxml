# RSS Feed Parser Example

This example demonstrates how to parse RSS/Atom feeds using Moxml, showcasing XPath queries, namespace handling, and data extraction.

## What This Example Demonstrates

- **XML Parsing**: Loading and parsing RSS feed XML
- **XPath Queries**: Using XPath to extract specific elements
- **Namespace Handling**: Working with Dublin Core (dc), Content, and Atom namespaces
- **Element Traversal**: Navigating the document structure
- **CDATA Sections**: Extracting content from CDATA blocks
- **Error Handling**: Proper error handling with Moxml exceptions

## Files

- `rss_parser.rb` - Main parser implementation
- `example_feed.xml` - Sample RSS 2.0 feed with multiple articles
- `README.md` - This file

## Running the Example

### Using the Example Feed

```bash
ruby examples/rss_parser/rss_parser.rb
```

### Using Your Own Feed

```bash
ruby examples/rss_parser/rss_parser.rb path/to/your/feed.xml
```

## Expected Output

```
Parsing RSS feed: examples/rss_parser/example_feed.xml
================================================================================

Feed: Tech News Daily
URL: https://technews.example.com
Description: Your daily dose of technology news

Articles:

================================================================================
Title: Ruby 3.4 Released with Performance Improvements
Link: https://technews.example.com/ruby-3-4-released
Author: Jane Smith
Published: Wed, 30 Oct 2024 09:00:00 GMT
Categories: Programming, Ruby
--------------------------------------------------------------------------------
Description: Ruby 3.4 brings significant performance improvements and new features

Full Content:
        <p>The Ruby core team has announced the release of Ruby 3.4, featuring:</p>
        <ul>
          <li>30% faster execution for common patterns</li>
          <li>Improved memory management</li>
          <li>New standard library additions</li>
        </ul>
================================================================================

[Additional articles...]

Summary:
Total articles: 4
Authors: Jane Smith, John Doe, Alice Johnson, Bob Williams
Categories: Programming (2), Ruby (1), XML (2), API (1), Design (1), XPath (1)
```

## Key Concepts

### XPath Queries

The example uses various XPath patterns:

```ruby
# Simple path - get channel title
doc.xpath('//channel/title')

# Namespaced element - get Dublin Core creator
item.xpath('./dc:creator', 'dc' => 'http://purl.org/dc/elements/1.1/')

# Multiple results - get all categories
item.xpath('./category')
```

### Namespace Handling

RSS feeds often use multiple namespaces:

```ruby
namespaces = {
  'dc' => 'http://purl.org/dc/elements/1.1/',      # Dublin Core
  'content' => 'http://purl.org/rss/1.0/modules/content/',  # Content
  'atom' => 'http://www.w3.org/2005/Atom'          # Atom
}

# Query with namespace
author = item.at_xpath('./dc:creator', namespaces)
```

### CDATA Content

Extract HTML/XML content preserved in CDATA sections:

```ruby
content_node = item.at_xpath('./content:encoded', namespaces)
content = content_node&.text&.strip
```

### Error Handling

Proper error handling for parse and XPath errors:

```ruby
begin
  doc = @moxml.parse(xml_content)
rescue Moxml::ParseError => e
  puts "Failed to parse RSS feed: #{e.message}"
  exit 1
end
```

## Code Structure

### Article Class

Represents a single RSS article with:
- Title, link, description
- Full content (from CDATA)
- Author (from dc:creator)
- Publication date
- Categories

### RSSParser Class

Main parser with methods:
- `parse` - Parse the feed and return Article objects
- `parse_item` - Extract data from a single RSS item
- `extract_text` - Helper for safe text extraction

## Customization

### Adding More Fields

To extract additional RSS fields, add to `parse_item`:

```ruby
# Extract guid
guid = extract_text(item, './guid')

# Extract enclosure (podcast, etc.)
enclosure = item.at_xpath('./enclosure')
if enclosure
  url = enclosure['url']
  type = enclosure['type']
  length = enclosure['length']
end
```

### Supporting Atom Feeds

Modify the parser to support Atom feed format:

```ruby
# Atom uses different element names
if doc.xpath('//feed').any?  # Atom feed
  items = doc.xpath('//entry')
  # Extract with Atom element names: entry, id, summary, etc.
end
```

## Learning Points

1. **XPath is powerful**: One query can extract multiple elements
2. **Namespaces are important**: Many RSS extensions use namespaces
3. **CDATA preserves markup**: Use for HTML/XML content within RSS
4. **Safe navigation**: Use `&.` operator and nil checks
5. **Error handling matters**: Always handle parse and query errors

## Next Steps

- Try parsing different RSS feeds from the web
- Add support for podcast feeds (enclosures)
- Implement feed validation
- Create an RSS feed aggregator
- Export articles to different formats (JSON, Markdown, etc.)

## Related Examples

- [Web Scraper](../web_scraper/) - Similar DOM navigation techniques
- [API Client](../api_client/) - XML generation and parsing