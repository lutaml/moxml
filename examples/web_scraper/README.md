# Web Scraper Example

This example demonstrates how to scrape data from HTML/XML documents using Moxml, showcasing table extraction, DOM navigation, and attribute access.

## What This Example Demonstrates

- **HTML Parsing**: Parsing HTML as XML for data extraction
- **Table Scraping**: Extracting structured data from HTML tables
- **DOM Navigation**: Traversing the document structure
- **Attribute Access**: Reading element attributes and data attributes
- **XPath Patterns**: Various XPath selectors for element selection
- **Data Structuring**: Converting scraped data into Ruby objects

## Files

- `web_scraper.rb` - Main scraper implementation
- `example_page.html` - Sample HTML page with programming language statistics
- `README.md` - This file

## Running the Example

### Using the Example Page

```bash
ruby examples/web_scraper/web_scraper.rb
```

### Using Your Own HTML

```bash
ruby examples/web_scraper/web_scraper.rb path/to/your/page.html
```

## Expected Output

```
Scraping HTML page: examples/web_scraper/example_page.html
================================================================================
Programming Language Statistics Scraper
================================================================================

Page Title: Programming Language Statistics - 2024

Summary:
  10 total languages tracked
  Last updated: October 30, 2024

Languages Extracted: 10
--------------------------------------------------------------------------------
1. Python (Interpreted) - 95.5% | Created: 1991 | Uses: Data Science, Web, AI
2. JavaScript (Interpreted) - 94.2% | Created: 1995 | Uses: Web Development
3. Java (Compiled) - 89.7% | Created: 1995 | Uses: Enterprise, Android
[...]

Category Statistics:
--------------------------------------------------------------------------------
Interpreted: 3 languages, avg 85.0%, top: Python
Compiled: 7 languages, avg 70.1%, top: Java

Detailed Information:
--------------------------------------------------------------------------------
python:
  Paradigm: Multi-paradigm: object-oriented, procedural, functional
  Typing: Dynamic, strong
  Community: Very large and active
  Learning Curve: Beginner-friendly
[...]

XPath Pattern Demonstrations
================================================================================
1. All table headers (//th):
   Found 12 headers: Rank, Language, Category, ...
[...]
```

## Key Concepts

### Table Scraping

Extract data from HTML tables systematically:

```ruby
# Find table by ID
table = doc.at_xpath("//table[@id='popularity-table']")

# Get all rows
rows = table.xpath('.//tbody/tr')

# Extract cells from each row
rows.each do |row|
  cells = row.xpath('./td')
  rank = cells[0].text.strip
  name = cells[1].text.strip
  # ...
end
```

### Attribute Access

Read element attributes using the `[]` operator:

```ruby
# Get data attribute
score = cell['data-score']

# Get class attribute
class_name = element['class']

# Check if attribute exists
if row['data-language']
  lang = row['data-language']
end
```

### XPath Patterns

The example demonstrates various XPath patterns:

```ruby
# By ID
doc.at_xpath("//div[@id='summary']")

# By class (contains for multi-class support)
doc.xpath("//*[contains(@class, 'language-name')]")

# By attribute existence
doc.xpath("//tr[@data-language]")

# Combining conditions
doc.xpath("//div[contains(@class, 'stats-card') and @data-language]")

# Direct descendants only
element.xpath('./td')  # Not './/td'
```

### DOM Navigation

Navigate the document tree:

```ruby
# Get parent
parent = element.parent

# Get children
children = element.children

# Get siblings
next_elem = element.next_sibling
prev_elem = element.previous_sibling
```

### Error Handling

Handle parsing errors gracefully:

```ruby
begin
  doc = @moxml.parse(html_content)
rescue Moxml::ParseError => e
  puts "Failed to parse HTML: #{e.message}"
  exit 1
end
```

## Code Structure

### Language Class

Represents a programming language with:
- Rank, name, category
- Popularity score
- Year created
- Primary use cases

### CategoryStats Class

Represents category statistics:
- Category name
- Language count
- Average score
- Top language

### WebScraper Class

Main scraper with methods:
- `scrape` - Main scraping entry point
- `extract_page_title` - Get page title
- `extract_summary` - Extract summary statistics
- `extract_languages_table` - Parse language table
- `extract_category_stats` - Parse category table
- `extract_detailed_info` - Parse detail cards

## XPath Pattern Reference

### Basic Selectors

```ruby
# All elements of a type
doc.xpath('//div')

# Element by ID
doc.at_xpath("//div[@id='content']")

# Element by class (single class)
doc.xpath("//div[@class='card']")

# Element by class (multiple classes)
doc.xpath("//*[contains(@class, 'card')]")
```

### Attribute Selectors

```ruby
# Has attribute
doc.xpath("//tr[@data-language]")

# Attribute equals value
doc.xpath("//input[@type='text']")

# Attribute contains value
doc.xpath("//div[contains(@class, 'active')]")
```

### Hierarchical Selectors

```ruby
# Direct child
div.xpath('./p')  # Only direct <p> children

# Any descendant
div.xpath('.//p')  # All <p> descendants

# Parent
element.parent

# Sibling
element.next_sibling
```

### Combining Conditions

```ruby
# AND condition
doc.xpath("//div[@class='card' and @id='main']")

# Multiple conditions
doc.xpath("//tr[contains(@class, 'row') and @data-id]")
```

## Customization

### Scraping Different Tables

Modify XPath selectors for your table structure:

```ruby
# Different table structure
table = doc.at_xpath("//table[@class='data-table']")
headers = table.xpath('.//thead/tr/th').map(&:text)
rows = table.xpath('.//tbody/tr')
```

### Handling Complex HTML

For nested structures:

```ruby
# Extract nested data
card.xpath('.//div[@class="section"]').each do |section|
  title = section.at_xpath('./h3').text
  items = section.xpath('.//li').map(&:text)
end
```

### Data Cleaning

Clean extracted text:

```ruby
# Strip whitespace
text = element.text.strip

# Remove special characters
text = text.gsub(/[^\w\s]/, '')

# Parse numbers
score = text.delete('%').to_f
```

## Learning Points

1. **HTML as XML**: Well-formed HTML can be parsed as XML
2. **XPath is powerful**: One query can find many elements
3. **Attributes are key**: Use data attributes for reliable scraping
4. **Structure matters**: Understand the DOM structure before scraping
5. **Clean data**: Always clean and validate scraped data
6. **Error handling**: Handle missing elements gracefully

## Best Practices

1. **Use specific selectors**: Prefer IDs over classes when available
2. **Validate data**: Check for nil/empty values
3. **Handle errors**: Wrap parsing in begin/rescue blocks
4. **Clean text**: Strip whitespace and normalize data
5. **Document structure**: Understand the HTML before writing XPath
6. **Test thoroughly**: Test with different HTML structures

## Common Issues

### Issue: Element not found

```ruby
# Bad - will raise error if not found
title = doc.xpath('//title').first.text

# Good - safe navigation
title = doc.at_xpath('//title')&.text || 'Unknown'
```

### Issue: Incorrect XPath

```ruby
# Wrong - searches entire document
row.xpath('//td')

# Correct - searches within row only
row.xpath('./td')
```

### Issue: Class matching

```ruby
# Won't work with multiple classes
div.xpath("//div[@class='card active']")

# Works with multiple classes
div.xpath("//div[contains(@class, 'card')]")
```

## Next Steps

- Scrape real websites (check robots.txt and terms of service)
- Add data export (CSV, JSON)
- Implement pagination handling
- Add retry logic for failed requests
- Create scrapers for different domains
- Implement data validation

## Related Examples

- [RSS Parser](../rss_parser/) - Similar XPath techniques for RSS
- [API Client](../api_client/) - XML generation and parsing