# Consistency Tests

## Purpose

This directory contains cross-adapter consistency tests that verify all adapters produce equivalent results for the same operations. These tests act as a quality gate to ensure adapter parity.

## What Should Be Placed Here

- ✅ Tests verifying all adapters produce equivalent XML output
- ✅ Tests ensuring API parity across adapters
- ✅ Tests catching adapter-specific quirks
- ✅ Tests for serialization consistency
- ✅ Tests for parsing equivalence

## What Should NOT Be Placed Here

- ❌ Adapter-specific implementation tests (use adapter/ instead)
- ❌ Unit tests (use unit/ instead)
- ❌ Performance benchmarks (use performance/ instead)
- ❌ Documentation examples (use examples/ instead)

## How to Run

```bash
# Run all consistency tests
bundle exec rake spec:consistency

# Run specific consistency test
bundle exec rspec spec/consistency/adapter_parity_spec.rb
```

## Directory Structure

```
consistency/
└── adapter_parity_spec.rb    # Ensures all adapters produce equivalent results
```

## Writing Consistency Tests

Consistency tests should compare output across all adapters:

```ruby
RSpec.describe "Adapter Parity" do
  describe "Serialization consistency" do
    it "produces equivalent XML across adapters" do
      results = {}

      Moxml::Adapter::AVALIABLE_ADAPTERS.each do |adapter|
        Moxml.with_config(adapter) do
          doc = Moxml.parse("<root><child>text</child></root>")
          results[adapter] = doc.to_xml
        end
      end

      # All results should be equivalent (allowing for formatting differences)
      expect(results.values.uniq.length).to eq(1)
    end
  end
end
```

## Purpose

These tests ensure that:
1. Users can switch adapters without changing behavior
2. All adapters implement the same API surface
3. No adapter-specific bugs leak into user code
4. Documentation examples work with all adapters

## CI Integration

Consistency tests should run:
- On every pull request
- Before releases
- As a quality gate
- To catch regressions