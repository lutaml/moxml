# SAX Parsing Examples

This directory contains practical examples demonstrating Moxml's SAX (Simple API for XML) parsing capabilities.

## Files

- `example.xml` - Sample XML file with book data
- `simple_parser.rb` - Basic SAX parsing with both class and block handlers
- `data_extractor.rb` - Extract specific data using ElementHandler
- `large_file.rb` - Memory-efficient streaming processor

## Running Examples

Make sure you have moxml installed:

```bash
gem install moxml
```

Then run any example:

```bash
ruby simple_parser.rb
ruby data_extractor.rb  
ruby large_file.rb
```

## What Each Example Demonstrates

### simple_parser.rb
- Basic handler creation
- Using both class-based and block-based handlers
- Handling different event types
- Comparing the two approaches

### data_extractor.rb
- Using ElementHandler for context-aware parsing
- Path matching with regex
- Extracting structured data
- Accumulating text across multiple character events

### large_file.rb
- Memory-efficient streaming
- Processing records without loading entire document
- Immediate output to avoid memory accumulation
- Best practices for large file handling

## Learn More

See the comprehensive SAX Parsing Guide in `docs/_guides/sax-parsing.adoc` for detailed documentation, patterns, and best practices.
