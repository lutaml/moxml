# Entity Support for lutaml-model Team

## Overview

Moxml now supports entity restoration during parsing. This feature ensures that XML entities (like `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`) are preserved as `EntityReference` nodes rather than being resolved to their character values during parsing.

## Key Concept: Entity Restoration

By default, XML parsers resolve entities during parsing:
- Input: `<root>foo&amp;bar</root>`
- Default behavior: Text node contains `foo&bar` (resolved `&`)
- With entity restoration: Text node contains `foo` + EntityReference `&amp;` + Text node `bar`

## Enabling Entity Restoration

### Option 1: Per-Context Configuration

```ruby
context = Moxml.new(:nokogiri, restore_entities: true)
doc = context.parse('<root>foo&amp;bar</root>')
# doc.to_xml will preserve &amp; as EntityReference
```

### Option 2: Global Configuration

```ruby
Moxml.configure do |config|
  config.restore_entities = true
end
```

## Preloading Entity Sets

You can preload standard entity sets (HTML5, MathML, ISO) for faster entity resolution:

```ruby
context = Moxml.new(:nokogiri,
  restore_entities: true,
  preload_entity_sets: [:html5, :mathml]
)
```

## W3C XML Core WG Compliance

Per W3C XML Core WG guidance:
- Standard XML entities (`amp`, `lt`, `gt`, `quot`, `apos`) are implicitly declared per XML spec
- The `EntityRegistry` class tracks all known entities and their Unicode codepoints
- Entity names are preserved through round-trip serialization

## What lutaml-model Needs to Know

### 1. Document Structure with Entities

When entity restoration is enabled, documents containing entities will have mixed node types:

```
Document
└── Element: root
    ├── Text: "foo"
    ├── EntityReference: "amp"  # Represents &
    └── Text: "bar"
```

### 2. Serialization

`doc.to_xml` will serialize EntityReference nodes as proper XML entity syntax:
- `EntityReference("amp")` → `&amp;`
- `EntityReference("lt")` → `&lt;`
- etc.

### 3. XPath Queries

EntityReference nodes participate in XPath queries like any other node. You can query for them specifically if needed.

### 4. Configuration Inheritance

When using `Moxml::Context`, the entity restoration setting is preserved through document operations. However, when creating new contexts, you need to set the option explicitly.

## Example Usage in lutaml-model

```ruby
# Parse XML with entities preserved
context = Moxml.new(:nokogiri, restore_entities: true)
doc = context.parse(your_xml_string)

# Serialize back - entities are preserved
output = doc.to_xml
```

## Testing Considerations

When writing tests for models that handle XML with entities:
1. Enable `restore_entities: true` in your test context
2. Verify that EntityReference nodes are created for entities in text
3. Test round-trip: parse → serialize → parse should preserve entities

## Files of Interest

- `lib/moxml/entity_registry.rb` - Entity definitions and lookup
- `lib/moxml/config.rb` - Configuration options
- `lib/moxml/document_builder.rb` - Entity restoration logic
- `lib/moxml/entity_reference.rb` - EntityReference node class
