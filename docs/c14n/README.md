# Canonicalization (C14N)

Canonicalization is the load-bearing primitive for XML signature and a
top-level moxml feature, sibling to `Moxml::XPath`, `Moxml::Builder`,
and `Moxml::SAX`. Two documents that differ only in surface
representation (whitespace, attribute order, namespace prefix choice)
produce identical canonical bytes.

## Pages

- [Algorithms](algorithms.md) — Inclusive C14N 1.0/1.1 (canon-port) and
  Exclusive C14N 1.0 (moxml-native), the data model, output invariants,
  and adapter delegation.
- [API](api.md) — the full public surface: canonicalize, exclusive,
  subset, digests, and the comparison helper.
- [Examples](examples.md) — patterns: whole-document, subset,
  cross-adapter verification, digests.

## Quick start

```ruby
# Canonical octets (inclusive C14N 1.0)
Moxml::C14n.canonicalize(node_or_xml)

# Exclusive C14N 1.0 (signatures over moved subdocuments)
Moxml::C14n.canonicalize_exclusive(node_or_xml,
                                   inclusive_namespaces: ["foo"])

# Node-set subset canonicalization (same-document references)
Moxml::C14n.canonicalize_subset(node_or_xml, "//signed")

# Canonical comparison (testing, regression, signature debugging)
Moxml::C14n.same_canonical_form?(left, right)
```

`node_or_xml` accepts a `Moxml::Node`, `Moxml::Document`, or XML
`String`. Engines without a native canonicalizer take the pure-Ruby
path — results are byte-identical across adapters, which is what keeps
cross-adapter signature verification sound.
