# C14N algorithms

## Inclusive C14N 1.0 / 1.1

- W3C: <https://www.w3.org/TR/xml-c14n/>, <https://www.w3.org/TR/xml-c14n11/>
- Implementation: **ported from `lutaml/canon`** (~1,200 lines)
- Files: `lib/moxml/c14n/inclusive_10.rb`, `inclusive_11.rb`,
  `data_model.rb`, `processor.rb`, `namespace_handler.rb`,
  `attribute_handler.rb`, `xml_base_handler.rb`, `character_encoder.rb`,
  `node.rb`, `nodes/*.rb`
- "Attracts" ancestor context: at the apex, every in-scope namespace is
  rendered, including those inherited from outside the canonicalization
  subset.

## Exclusive C14N 1.0

- W3C: <https://www.w3.org/TR/xml-exc-c14n/>
- Implementation: **moxml-native** (canon does not implement exclusive)
- Files: `lib/moxml/c14n/exclusive.rb`, `writer.rb`, `namespace_context.rb`
- "Repels" ancestor context: only namespaces visibly used by the apex
  element's qualified name or attributes are rendered. Keeps signatures
  valid when subdocuments move between XML contexts (e.g., into a SOAP
  envelope).

## Adapter delegation

Adapters whose engines ship a native canonicalizer delegate through a
lazy byte-safety probe — the pure-Ruby path remains the fallback and
the arbiter: all routes produce byte-identical output (pinned by
`spec/moxml/c14n/adapter_delegation_spec.rb`).

- **leptris**: engine-delegated inclusive C14N — an order of magnitude
  faster than the Ruby path on large documents.
- **nokogiri**: libxml2 native canonicalization.

## Data model

The canon-derived inclusive engines walk an intermediate data model
(`Moxml::C14n::Nodes::*`) rather than the live `Moxml::Node` tree,
because canonicalization needs:

- **Node-set membership flags** for subset canonicalization (spec §3).
- **Sorted namespace and attribute axes** per spec §2.3 / §2.4.
- **xml:base fixup** per RFC 3986 with C14N 1.1 modifications.
- **xml:\* inheritable attribute resolution** (xml:lang, xml:space)
  from omitted ancestors.

The data model is built from `Moxml::Node` via `Moxml::C14n::DataModel`.

## Output invariants

- UTF-8 encoded, no BOM
- NFC characters preserved
- Document-order traversal
- Entity references: `&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;`
- Attribute values: also escape `"`, tab, LF, CR
- Empty elements expanded: `<foo/>` → `<foo></foo>`
- Line endings normalized to LF (the parser already does this)

## Cross-verification

The libxmlsec1-produced fixtures in `spec/fixtures/xmldsig/` verify
byte-exact against our C14N output — the implementation matches
libxml2's C-based canonicalization for the cases the Ruby reference
exercises.
