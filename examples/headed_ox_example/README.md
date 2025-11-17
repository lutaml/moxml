# HeadedOx Demo

This example demonstrates the HeadedOx adapter, which combines:
- Ox's fast C-based XML parsing
- Moxml's comprehensive pure Ruby XPath 1.0 engine

## What is HeadedOx?

HeadedOx is a hybrid adapter that provides:
- **Fast parsing:** Uses Ox's C-based parser for speed
- **Full XPath 1.0:** All 27 XPath functions and 6 common axes
- **Production ready:** 99.20% test pass rate (1,992/2,008 tests)
- **Pure Ruby XPath:** Debuggable implementation with expression caching
- **Best of both:** Combines Ox speed with comprehensive XPath support

## Running the Demo

### For Development (from gem source):
```bash
# From the moxml root directory
bundle exec ruby examples/headed_ox_example/headed_ox_demo.rb
```

Note: The example uses `require_relative` to load Moxml from source, which requires
`bundle exec` to properly resolve dependencies in development.

### After Installation:
```bash
# When using the installed gem
ruby headed_ox_demo.rb
```

## Features Demonstrated

1. **Descendant queries** - `//book` syntax
2. **Attribute selection** - `@price` syntax
3. **Predicates** - `[@price < 20]` filtering
4. **XPath functions** - count(), sum(), string(), contains()
5. **Complex queries** - Combining multiple features
6. **Variable binding** - `$var` support

## Output

The demo shows HeadedOx executing various XPath queries on a sample library XML,
demonstrating the full range of XPath 1.0 capabilities.

## Expected Output

```
============================================================
HeadedOx Demo - Comprehensive XPath on Fast Ox Parsing
============================================================

1. Find all books:
Found 3 books

2. Get all prices:
Prices: 15.99, 25.99, 12.99

3. Find cheap books (< $20):
  - Programming Ruby: $15.99
  - Programming JavaScript: $12.99

4. XPath functions:
  Total books: 3
  Total price: $54.97
  First title: Programming Ruby

5. Books with 'Ruby' in title:
  - Programming Ruby

6. Using variables:
Books under $20: 2

============================================================
HeadedOx provides full XPath 1.0 support!
============================================================
```

## Why Choose HeadedOx?

Use HeadedOx when you need:
- Fast XML parsing (Ox's strength)
- Comprehensive XPath beyond basic locate()
- XPath 1.0 functions like count(), sum(), contains()
- Complex predicates and expressions
- Debuggable XPath implementation
- Production-ready stability (99.20% test coverage)

See `docs/HEADED_OX_LIMITATIONS.md` for detailed capabilities and known limitations.
