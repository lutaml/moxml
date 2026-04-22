# TODO 7: HeadedOx Adapter Limitations (15 Skipped Tests)

## Problem

HeadedOx (Ox + pure-Ruby XPath engine) has 15 skipped tests representing 7
distinct limitation areas. Some require upstream Ox gem enhancements; others
need investigation or Moxml-side fixes.

Full details in `docs/_pages/headed-ox-limitations.adoc`.

## Limitation Areas

### 7a. XPath `@*` Attribute Wildcard (3 tests)

The XPath parser does not support wildcard in the attribute axis.

**Tests:**
- `spec/moxml/xpath/compiler_spec.rb:156` — descendant-or-self wildcards
- `spec/moxml/xpath/compiler_spec.rb:192` — attribute axis wildcards
- `spec/moxml/xpath/axes_spec.rb:225` — attribute + predicate combinations

**Workaround:** Use `element.attributes.values` via Ruby enumeration.

### 7b. Namespace Methods (4 tests)

Ox does not expose namespace information through its public API. The adapter
cannot implement `node.namespace`, `node.namespaces`, or namespace inheritance.

**Tests:**
- `spec/integration/shared_examples/edge_cases.rb:93` — default namespace changes
- `spec/integration/shared_examples/edge_cases.rb:119` — recursive namespace defs
- `spec/integration/shared_examples/edge_cases.rb:139` — namespace-prefixed attr access
- `spec/integration/shared_examples/integration_workflows.rb:83` — complex namespaces

**Requires:** Ox gem API enhancement (namespace accessors on `Ox::Element`).

### 7c. Text Content from Nested XPath Results (4 tests)

Accessing text content from child elements of XPath result nodes returns empty
strings. Likely a node wrapping or text node handling issue in HeadedOx.

**Tests:**
- `spec/moxml/adapter/headed_ox_spec.rb:74` — string functions in predicates
- `spec/moxml/adapter/headed_ox_spec.rb:82` — position functions
- `spec/moxml/adapter/headed_ox_spec.rb:304` — last() function
- `spec/integration/shared_examples/node_wrappers/node_behavior.rb:113` — XPath text access

**Needs:** Investigation — check node wrapping and text node registration.

### 7d. CDATA `]]>` Escaping (2 tests)

Ox serializes CDATA sections as-is without splitting on `]]>` sequences, which
violates the XML spec.

**Tests:**
- `spec/integration/shared_examples/edge_cases.rb:39`
- `spec/integration/shared_examples/node_wrappers/cdata_behavior.rb:44`

**Requires:** Ox gem enhancement or Moxml-side serialization override.

### 7e. Parent Node Setter (1 test)

Ox has no native method to change a node's parent after creation.

**Test:**
- `spec/integration/shared_examples/integration_workflows.rb:126`

**Requires:** Ox gem reparenting API or workaround via remove + re-add.

### 7f. Namespace-Aware XPath with Predicates (1 test)

Queries like `//xmlns:item[@id="123"]` return empty results under HeadedOx.

**Test:**
- `spec/integration/shared_examples/integration_workflows.rb:63`

**Needs:** Investigation — check namespace resolution in predicate context.

### 7g. Wildcard Element Counting (1 test)

`//*` returns a different count (6) vs Nokogiri (7+), likely due to Ox's DOM
structure.

**Test:**
- `spec/moxml/xpath/compiler_spec.rb:156`

**Impact:** Low — real-world queries typically use specific element names.

## Files

- `docs/_pages/headed-ox-limitations.adoc` — full documentation
- `lib/moxml/adapter/headed_ox.rb`
- `lib/moxml/adapter/ox.rb`
- `lib/moxml/xpath/` — pure-Ruby XPath engine
- All spec files listed above
