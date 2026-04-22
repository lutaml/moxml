# TODO 2: Model-Driven Entity Restoration

## Problem

The `restore_entities` feature in `DocumentBuilder` is hardcoded to only handle
the 5 standard XML entities (amp, lt, gt, quot, apos). It ignores the
EntityRegistry entirely — despite EntityRegistry knowing 2125+ entities from
the W3C HTML/MathML set. This means non-standard entities like `&nbsp;`,
`&copy;`, `&mdash;` are never restored, which is the core round-trip problem
that motivated the entire entity feature.

Additionally, the restoration logic lives in DocumentBuilder with hardcoded
knowledge that belongs in the model layer.

## Current State (verified)

`lib/moxml/document_builder.rb:80-110` — `restore_entities_in_text`:
```ruby
entity_chars = {
  "<" => "lt", ">" => "gt", "&" => "amp",
  '"' => "quot", "'" => "apos",
}
```

This is a hardcoded lookup that duplicates knowledge already in EntityRegistry.
It only triggers for characters `<`, `>`, `&`, `"`, `'` — the regex guard
`/[<>&"']/` on line 73 prevents it from ever seeing characters like U+00A0
(non-breaking space, `&nbsp;`).

**Critical**: Because only Nokogiri has `create_native_entity_reference`
(see TODO 1), `restore_entities` raises `NotImplementedError` on all other
adapters even for the 5 standard entities.

## XML Entity Model

XML has a clear entity model:

1. **5 predefined entities** (amp, lt, gt, quot, apos) — always available per
   XML spec. These characters MUST be entity-encoded in certain contexts
   (e.g., `<` and `&` in text content).

2. **DTD-declared entities** — declared via `<!ENTITY name "value">` in the
   document's DOCTYPE internal subset or external subset.

3. **API-supplied entities** — registered by the user via
   `EntityRegistry.register` or `entity_provider` callback.

4. **Bundled detection set** — the W3C HTML/MathML entities bundled in
   `data/w3c_entities.json`. These are not "declared" in any DTD but are
   recognized by Moxml for restoration purposes.

The EntityRegistry already knows about categories 1, 3, and 4. Category 2
(DTD parsing) is future work.

## Design: Model-Driven Restoration

EntityRegistry should be THE source of truth for "should this character become
an entity reference?" The restoration policy should be:

```ruby
# In EntityRegistry (or a cooperating policy object)
STANDARD_CODEPOINTS = [0x26, 0x3C, 0x3E, 0x22, 0x27].freeze  # amp, lt, gt, quot, apos

def should_restore?(codepoint, config:)
  name = primary_name_for_codepoint(codepoint)
  return false unless name

  # 1. The 5 standard XML entities are ALWAYS restored.
  #    These are syntactically required — the XML wouldn't be well-formed
  #    without encoding them.
  return true if STANDARD_CODEPOINTS.include?(codepoint)

  # 2. Non-standard entities: only if restore_entities is enabled.
  return false unless config.restore_entities

  # 3. In the future, strict vs lenient mode will gate this further.
  #    Strict: only if declared in DTD (not yet implemented).
  #    Lenient: any known entity name.
  true
end
```

### Changes to DocumentBuilder

Replace the hardcoded hash with delegation to the registry:

```ruby
def visit_text(node)
  prepared = adapter.prepare_for_new_document(node, @current_doc.native)
  content = adapter.text_content(node)

  if should_restore_entities?(content)
    restore_entities_in_text(content)
  else
    @node_stack.last&.add_child(Text.new(prepared, context))
  end
end

private

def should_restore_entities?(content)
  return false unless context.config.restore_entities
  # Scan for any character that the registry knows about
  content.to_s.chars.any? { |c| context.entity_registry.should_restore?(c.ord, config: context.config) }
end

def restore_entities_in_text(content)
  parent = @node_stack.last
  return unless parent

  content.to_s.chars.each do |char|
    codepoint = char.ord
    name = context.entity_registry.primary_name_for_codepoint(codepoint)

    if context.entity_registry.should_restore?(codepoint, config: context.config)
      entity_node = adapter.create_entity_reference(name)
      parent.add_child(EntityReference.new(entity_node, context))
    else
      text_node = adapter.create_text(char)
      parent.add_child(Text.new(text_node, context))
    end
  end
end
```

**Note**: This splits each text node into per-character nodes. For documents
with few entity references, this creates unnecessary overhead. A future
optimization should buffer consecutive non-entity characters into a single
text node.

### Performance Optimization (deferred)

Instead of character-by-character processing:
1. Scan the text for characters that have entity names in the registry
2. Split only at those positions, keeping runs of plain characters together
3. This reduces node count dramatically for typical documents

```ruby
def restore_entities_in_text(content)
  parent = @node_stack.last
  return unless parent

  buffer = +""
  content.to_s.chars.each do |char|
    codepoint = char.ord
    name = context.entity_registry.primary_name_for_codepoint(codepoint)

    if name && context.entity_registry.should_restore?(codepoint, config: context.config)
      # Flush buffer before entity
      if !buffer.empty?
        parent.add_child(Text.new(adapter.create_text(buffer), context))
        buffer.clear
      end
      parent.add_child(EntityReference.new(adapter.create_entity_reference(name), context))
    else
      buffer << char
    end
  end
  # Flush remaining buffer
  if !buffer.empty?
    parent.add_child(Text.new(adapter.create_text(buffer), context))
  end
end
```

## Files to Modify

- `lib/moxml/entity_registry.rb` — add `should_restore?` method
- `lib/moxml/document_builder.rb` — replace hardcoded entity_chars with registry-driven logic
