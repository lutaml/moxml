# Adapter Tests

## Purpose

This directory contains tests for adapter implementations. Each test verifies that an adapter correctly implements the adapter API contract and tests adapter-specific features.

## What Should Be Placed Here

- ✅ Tests for adapter API contract compliance (parse, create_*, serialize, xpath, etc.)
- ✅ Tests for adapter-specific features
- ✅ Tests for adapter workarounds/customizations
- ✅ Each adapter tested independently
- ✅ Adapter initialization and configuration tests

## What Should NOT Be Placed Here

- ❌ Tests for high-level wrapper behavior (use integration/ instead)
- ❌ Tests for cross-adapter consistency (use consistency/ instead)
- ❌ Tests for Moxml wrapper classes
- ❌ Performance benchmarks (use performance/ instead)

## How to Run

```bash
# Run all adapter tests
bundle exec rake spec:adapter

# Run specific adapter test
bundle exec rspec spec/adapter/nokogiri_spec.rb
```

## Directory Structure

```
adapter/
├── shared_examples/
│   └── adapter_contract.rb    # Defines the adapter API contract
├── libxml_spec.rb             # LibXML adapter implementation
├── nokogiri_spec.rb           # Nokogiri adapter implementation
├── oga_spec.rb                # Oga adapter implementation
├── ox_spec.rb                 # Ox adapter implementation
└── rexml_spec.rb              # REXML adapter implementation
```

## Adding a New Adapter

When adding a new adapter:

1. Create `spec/adapter/<adapter_name>_spec.rb`
2. Include the adapter contract:
   ```ruby
   RSpec.describe Moxml::Adapter::YourAdapter do
     around do |example|
       Moxml.with_config(:your_adapter, true, "UTF-8") do
         example.run
       end
     end

     it_behaves_like "adapter contract"
   end