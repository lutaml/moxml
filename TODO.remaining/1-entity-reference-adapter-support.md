# TODO 1: EntityReference Adapter Support for Ox, Oga, REXML, LibXML, HeadedOx

## Problem

Only the Nokogiri adapter implements `create_native_entity_reference` and maps
its native type to `:entity_reference` in `node_type`. The other 5 adapters
will raise `NotImplementedError` if `restore_entities` is enabled or if any
code path calls `create_entity_reference`. This makes the entire
EntityReference feature **non-functional** outside Nokogiri.

## Current State (verified)

| Adapter   | `create_native_entity_reference` | `node_type` mapping | Serialization | Status |
|-----------|----------------------------------|---------------------|---------------|--------|
| Nokogiri  | Done (`Nokogiri::XML::EntityReference.new`) | Done | Native | Working |
| Ox        | Missing | Missing | Uses `Ox.dump` (C-level, won't handle custom types) | Broken |
| HeadedOx  | Missing (inherits Ox) | Missing | Same as Ox | Broken |
| Oga       | Missing | Missing | Uses `CustomizedOga::XmlGenerator` | Broken |
| REXML     | Missing | Missing | Uses REXML's `write` | Broken |
| LibXML    | Missing | Missing | Uses custom serializer with wrapper detection | Broken |

## Architecture

EntityReference follows the same pattern as other non-native node types in Moxml:
a **wrapper class** that represents what the underlying library cannot express natively.

Each adapter needs three things:
1. **Wrapper class** (`CustomizedXxx::EntityReference`) — holds the entity name
2. **`node_type` mapping** — so `Node.wrap` can create the correct Moxml type
3. **Serialization** — so `to_xml` outputs `&name;`

The existing pattern: `CustomizedOx::Text` extends `::Ox::Node`,
`CustomizedOx::Attribute` extends `::Ox::Node`. EntityReference should follow suit.

### Serialization Challenge for Ox

Ox's `serialize` calls `::Ox.dump(node)` which is C-level — it only handles
Ox native types. For EntityReference wrappers to survive serialization, we need
one of:

- **Option A**: Custom serialization in the adapter that walks the tree manually,
  detecting EntityReference wrappers and emitting `&name;` directly.
- **Option B**: Convert EntityReferences to their text equivalent before calling
  `Ox.dump`, restoring them in a post-processing step. This is fragile.
- **Option C**: Override `serialize` for Element nodes to handle children
  individually, using `Ox.dump` for native children but handling wrappers
  directly.

**Recommended: Option A** — it's how `CustomizedOga::XmlGenerator` already works
for Oga. A similar tree-walking serializer for Ox gives full control.

For LibXML, the existing serializer already checks `node.respond_to?(:to_xml)`
for wrapper classes, so adding an EntityReference wrapper with `to_xml` returning
`"&#{name};"` should integrate cleanly.

## Implementation Steps

### Ox Adapter

1. Create `lib/moxml/adapter/customized_ox/entity_reference.rb`:
   ```ruby
   module Moxml::Adapter::CustomizedOx
     class EntityReference < ::Ox::Node
       attr_reader :name

       def initialize(name)
         @name = name
         super()  # Ox::Node requires no args or a value
       end

       def to_xml
         "&#{@name};"
       end
       alias to_s to_xml
     end
   end
   ```

2. Add to `lib/moxml/adapter/ox.rb`:
   - `create_native_entity_reference(name)` → `CustomizedOx::EntityReference.new(name)`
   - `node_type`: add `when CustomizedOx::EntityReference then :entity_reference`
   - `patch_node`: handle EntityReference wrapper in child list
   - `entity_reference_name(node)`: return `node.name`
   - Serialization: handle EntityReference children when walking the tree

3. Add to `lib/moxml/adapter/ox.rb` `unpatch_node`: return wrapper as-is
   (it extends Ox::Node so it can stay in the tree)

### HeadedOx Adapter

HeadedOx inherits from Ox, so it gets Ox's EntityReference support
automatically once Ox is done. Verify that the XPath engine doesn't
break when encountering EntityReference nodes in the tree.

### Oga Adapter

1. Create `lib/moxml/adapter/customized_oga/entity_reference.rb`:
   ```ruby
   module Moxml::Adapter::CustomizedOga
     class EntityReference
       attr_reader :name

       def initialize(name)
         @name = name
       end

       def to_xml
         "&#{@name};"
       end
     end
   end
   ```

2. Add to `lib/moxml/adapter/oga.rb`:
   - `create_native_entity_reference(name)` → `CustomizedOga::EntityReference.new(name)`
   - `node_type`: add `when CustomizedOga::EntityReference then :entity_reference`
   - Update `CustomizedOga::XmlGenerator` to handle EntityReference children
   - `entity_reference_name(node)`: return `node.name`

### REXML Adapter

1. Investigate: REXML has `REXML::Entity` and `REXML::EntityRef` classes.
   Check if they can be used as native entity reference nodes, or if a
   wrapper is needed.

2. Add to `lib/moxml/adapter/rexml.rb`:
   - `create_native_entity_reference(name)` — native or wrapper
   - `node_type`: add mapping
   - `entity_reference_name(node)`

### LibXML Adapter

1. Investigate: LibXML Ruby has `LibXML::XML::Node::ENTITY_REF_NODE` constant
   (value 5). Check if native entity reference nodes can be created.

2. Create `lib/moxml/adapter/customized_libxml/entity_reference.rb` if needed.

3. Add to `lib/moxml/adapter/libxml.rb`:
   - `create_native_entity_reference(name)`
   - `node_type`: add `ENTITY_REF_NODE` mapping or wrapper mapping
   - `entity_reference_name(node)`
   - The existing serializer already handles wrappers with `to_xml` —
     verify EntityReference works in this path.

## Files to Create/Modify

### New Files
- `lib/moxml/adapter/customized_ox/entity_reference.rb`
- `lib/moxml/adapter/customized_oga/entity_reference.rb`
- Possibly: `lib/moxml/adapter/customized_libxml/entity_reference.rb`

### Modified Files
- `lib/moxml/adapter/ox.rb` — create_native_entity_reference, node_type, serialization
- `lib/moxml/adapter/oga.rb` — create_native_entity_reference, node_type, XmlGenerator
- `lib/moxml/adapter/rexml.rb` — create_native_entity_reference, node_type
- `lib/moxml/adapter/libxml.rb` — create_native_entity_reference, node_type
- `lib/moxml/adapter/headed_ox.rb` — verify inheritance works (likely no changes)
