# C14N API

`node_or_xml` accepts a `Moxml::Node`, `Moxml::Document`, or XML
`String` on every entry point.

## Convenience methods

```ruby
# Inclusive C14N 1.0
Moxml::C14n.canonicalize(node_or_xml, with_comments: false)

# Exclusive C14N 1.0
Moxml::C14n.canonicalize_exclusive(
  node_or_xml,
  with_comments: false,
  inclusive_namespaces: [],  # InclusiveNamespacesPrefixList parameter
)

# Inclusive C14N 1.1
Moxml::C14n.canonicalize_inclusive11(node_or_xml, with_comments: false)

# Node-set subset canonicalization: only nodes matched by the XPath
# render (position-path matching — see docs on enveloped signatures)
Moxml::C14n.canonicalize_subset(node_or_xml, "//signed",
                                with_comments: false)

# Canonical comparison: do two inputs share one canonical form?
# (inclusive C14N 1.0, comments dropped, on both sides)
Moxml::C14n.same_canonical_form?(left, right)  # nodes or raw strings
```

All canonicalize methods return canonical UTF-8 octet strings.

## Direct engine access

Used by the signature algorithms:

```ruby
Moxml::C14n::Inclusive10.new.canonicalize(node, with_comments:,
                                          inclusive_namespaces:)
Moxml::C14n::Inclusive11.new.canonicalize(node, with_comments:,
                                          inclusive_namespaces:)
Moxml::C14n::Exclusive.new.canonicalize(node, with_comments:,
                                        inclusive_namespaces:)
```

## Digests

`Node#digest` (engine-delegated where available) computes the canonical
digest of a subtree:

```ruby
node.digest                    # SHA-256 over inclusive C14N 1.0
node.digest(drop_ws_text: true)
```

## Backward-compat escape helpers

```ruby
Moxml::C14n.escape_text("a & b < c > d")
Moxml::C14n.escape_attribute(%(a"b\tc\nd))
```
