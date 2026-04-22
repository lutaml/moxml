# TODO 6: Ox Adapter Element Ordering Bug

## Problem

When round-tripping certain XML fixtures through the Ox adapter, child elements
are produced in a different order compared to Nokogiri, Oga, and REXML. This
causes cross-adapter consistency failures for `elements_with_attributes`
comparisons.

The semantic equivalence check (double round-trip) still passes, so the
document content is correct — only the ordering is wrong.

## Current State

Suppressed in `spec/consistency/round_trip_spec.rb:332` via
`KNOWN_ELEMENT_ORDERING_ISSUES` set. Affected fixture/adapter combinations:

```
niso-jats/element_citation.xml  nokogiri <-> ox
niso-jats/element_citation.xml  ox <-> oga
niso-jats/element_citation.xml  rexml <-> ox
```

## Investigation Needed

- Determine whether Ox's DOM building reorders nodes or if the issue is in
  Moxml's tree traversal during serialization.
- Check if Ox's `Ox::Element#nodes` preserves insertion order.
- Compare Ox's native serialization (`Ox.dump`) with Moxml's custom serializer
  to narrow down where the reorder happens.

## Files

- `spec/consistency/round_trip_spec.rb` — suppression set
- `lib/moxml/adapter/ox.rb` — serialization path
- `lib/moxml/adapter/customized_ox/` — wrapper classes involved in tree walk
