# Performance Tests

## Purpose

This directory contains performance benchmarks, memory profiling, and concurrency tests. These tests are optional and skipped by default to keep CI fast.

## What Should Be Placed Here

- ✅ Benchmark tests comparing adapter performance
- ✅ Memory consumption profiling
- ✅ Thread safety and concurrent access tests
- ✅ Performance regression tests
- ✅ Scalability tests with large documents

## What Should NOT Be Placed Here

- ❌ Functional correctness tests (use unit/ or integration/ instead)
- ❌ Documentation examples (use examples/ instead)
- ❌ Cross-adapter consistency tests (use consistency/ instead)

## How to Run

```bash
# Run all performance tests
bundle exec rake spec:performance

# Or explicitly with environment variable
RUN_PERFORMANCE=1 bundle exec rspec spec/performance/

# Run specific benchmark
bundle exec rspec spec/performance/xpath_benchmark_spec.rb --tag performance
```

## Directory Structure

```
performance/
├── xpath_benchmark_spec.rb        # XPath performance across adapters
├── benchmark_spec.rb              # General parsing/serialization benchmarks
├── memory_usage_spec.rb           # Memory consumption tests
└── thread_safety_spec.rb          # Concurrent access tests
```

## Writing Performance Tests

Performance tests should be tagged with `:performance`:

```ruby
RSpec.describe "XPath Performance", :performance do
  it "benchmarks xpath queries" do
    # Benchmark code
  end
end
```

## Configuration

Performance tests are skipped by default in `.rspec`:
```
--tag ~performance
```

Enable them with:
```bash
RUN_PERFORMANCE=1 bundle exec rspec
```

## CI Integration

Performance tests typically run:
- On-demand (manual trigger)
- Nightly builds
- Before releases
- Never on pull requests (too slow)

## Metrics

Performance tests should track:
- Execution time (iterations per second)
- Memory allocation
- Peak memory usage
- Thread safety (no race conditions)
- Scalability (linear vs. exponential growth)