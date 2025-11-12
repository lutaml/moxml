# Unit Tests

## Purpose

This directory contains pure unit tests for individual classes without adapter switching. Each test focuses on a single class's behavior, state management, and convenience APIs.

## What Should Be Placed Here

- ✅ Tests for individual class methods
- ✅ Tests for convenience APIs (e.g., `Element#set_attributes`)
- ✅ Tests for internal utilities
- ✅ Tests for configuration and setup
- ✅ Tests that use a single adapter (usually the default)
- ✅ Tests for class-level functionality independent of adapter implementation

## What Should NOT Be Placed Here

- ❌ Tests that switch between multiple adapters
- ❌ Tests for cross-adapter behavior
- ❌ Integration tests that involve multiple classes
- ❌ Performance benchmarks
- ❌ Documentation examples

## How to Run

```bash
# Run all unit tests
bundle exec rake spec:unit

# Run specific unit test file
bundle exec rspec spec/unit/moxml/element_spec.rb
```

## Directory Structure

```
unit/
├── moxml/              # Core moxml classes
│   ├── adapter/        # Adapter registry and base
│   └── xml_utils/      # Utility classes
└── moxml_spec.rb       # Top-level module tests