# Example Tests

## Purpose

This directory contains executable documentation examples. These tests verify that code examples from documentation and README work correctly and serve as living documentation.

## What Should Be Placed Here

- ✅ Tests for documentation examples
- ✅ Tests for README code snippets
- ✅ Examples that demonstrate API usage
- ✅ Tutorial-style example tests
- ✅ Tests that can be extracted for documentation

## What Should NOT Be Placed Here

- ❌ Comprehensive test coverage (use unit/ or integration/ instead)
- ❌ Edge case testing (use integration/ instead)
- ❌ Performance benchmarks (use performance/ instead)
- ❌ Adapter-specific tests (use adapter/ instead)

## How to Run

```bash
# Run all example tests
bundle exec rake spec:examples

# Run specific example test
bundle exec rspec spec/examples/basic_usage_spec.rb

# Examples can be skipped in CI
bundle exec rspec --tag ~examples
```

## Directory Structure

```
examples/
├── basic_usage_spec.rb        # README basic usage examples
├── namespace_examples_spec.rb # Namespace handling examples
├── xpath_examples_spec.rb     # XPath query examples
└── attribute_examples_spec.rb # Attribute manipulation examples
```

## Writing Example Tests

Example tests should:
1. Be simple and easy to understand
2. Demonstrate real-world usage patterns
3. Run with all adapters to ensure portability
4. Be suitable for extraction into documentation

```ruby
RSpec.describe "Basic Usage Examples" do
  Moxml::Adapter::AVALIABLE_ADAPTERS.each do |adapter_name|
    context "with #{adapter_name} adapter" do
      let(:context) { Moxml.new(adapter_name) }

      it "parses XML" do
        doc = context.parse("<root>Text</root>")
        expect(doc.root.text).to eq("Text")
      end
    end
  end
end
```

## Tagging

Example tests are tagged with `:examples` and can be excluded:

```ruby
RSpec.describe "Example", :examples do
  # ...
end