# Integration Tests

## Purpose

This directory contains integration tests that verify Moxml wrapper classes work correctly with all adapters. These tests use shared examples to ensure consistent behavior across different adapter implementations.

## What Should Be Placed Here

- ✅ Tests for wrapper classes working with all adapters
- ✅ Tests for complex workflows involving multiple classes
- ✅ Tests for edge cases that involve adapter interaction
- ✅ Shared examples that run for each adapter
- ✅ Cross-adapter behavioral consistency tests

## What Should NOT Be Placed Here

- ❌ Pure unit tests (use unit/ instead)
- ❌ Adapter-specific implementation tests (use adapter/ instead)
- ❌ Performance benchmarks (use performance/ instead)
- ❌ Documentation examples (use examples/ instead)

## How to Run

```bash
# Run all integration tests
bundle exec rake spec:integration

# Run specific integration test
bundle exec rspec spec/integration/all_adapters_spec.rb
```

## Directory Structure

```
integration/
├── shared_examples/
│   ├── node_wrappers/           # Node wrapper behavior tests
│   │   ├── attribute_behavior.rb
│   │   ├── cdata_behavior.rb
│   │   ├── comment_behavior.rb
│   │   ├── declaration_behavior.rb
│   │   ├── doctype_behavior.rb
│   │   ├── document_behavior.rb
│   │   ├── element_behavior.rb
│   │   ├── namespace_behavior.rb
│   │   ├── node_behavior.rb
│   │   ├── node_set_behavior.rb
│   │   ├── processing_instruction_behavior.rb
│   │   └── text_behavior.rb
│   ├── high_level/              # High-level pattern tests
│   │   ├── builder_behavior.rb
│   │   ├── context_behavior.rb
│   │   └── document_builder_behavior.rb
│   ├── edge_cases.rb            # Edge case scenarios
│   └── integration_workflows.rb # Complete workflows
└── all_adapters_spec.rb         # Runs all shared examples for all adapters
```

## Writing Integration Tests

Integration tests should be written as shared examples that can run with any adapter:

```ruby
RSpec.shared_examples "element wrapper behavior" do
  it "creates elements" do
    # Test that works with any adapter
  end
end
```

The `all_adapters_spec.rb` file runs these shared examples for each adapter.