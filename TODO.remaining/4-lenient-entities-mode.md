# TODO 4: Lenient Entities Mode

## Problem

XML only defines 5 predefined entities (amp, lt, gt, quot, apos). Any other
entity must be declared in a DTD. However, real-world XML documents frequently
use HTML entities (`&nbsp;`, `&copy;`) without DTD declarations — particularly
office documents (OOXML/ODF) and legacy systems.

Currently Moxml has no way to configure whether undeclared entities should be
preserved. The `restore_entities` flag is a boolean that enables restoration
for all known entities from the registry. There is no distinction between
"only DTD-declared" (strict) and "any recognized" (lenient).

## Design

### Config Option

Add `entity_restoration_mode` to Config with two values:

- `:strict` (default) — Only restore entities that are declared in the DTD
  internal subset. The 5 standard XML entities are always restored regardless
  (they are implicitly declared per XML spec). DTD parsing is prerequisite.

- `:lenient` — Restore any character that has a known entity name in the
  EntityRegistry. This covers the bundled W3C HTML/MathML set (2125 entities)
  plus any user-registered entities. No DTD required.

This replaces the boolean `restore_entities` which becomes a derived property:
- `restore_entities = true` + `entity_restoration_mode = :lenient` → restore all known
- `restore_entities = true` + `entity_restoration_mode = :strict` → restore only declared
- `restore_entities = false` → don't restore any

### EntityRegistry Enhancement

```ruby
class EntityRegistry
  def should_restore?(codepoint, config:)
    name = primary_name_for_codepoint(codepoint)
    return false unless name

    # Standard XML entities always restored (XML well-formedness requirement)
    return true if standard_entity?(codepoint)

    # Must have restoration enabled
    return false unless config.restore_entities

    case config.entity_restoration_mode
    when :lenient
      # Any known entity
      true
    when :strict
      # Only if declared in DTD (future: check DTD declarations)
      # For now, fall back to lenient behavior until DTD parsing is implemented
      true
    else
      false
    end
  end

  def standard_entity?(codepoint)
    STANDARD_ENTITIES.value?(codepoint)
  end
end
```

### User-Supplied Entities

Users can supply entities through three mechanisms:

1. **EntityRegistry.register** — programmatic registration:
   ```ruby
   context = Moxml.new(:nokogiri)
   context.entity_registry.register({ "myentity" => 0xABCD })
   ```

2. **entity_provider callback** — for custom/external entity sources:
   ```ruby
   Moxml.new(:nokogiri) do |c|
     c.entity_load_mode = :custom
     c.entity_provider = -> { { "myentity" => 0xABCD } }
   end
   ```

3. **Bundled W3C set** — loaded by default in `:required` mode (2125 entities
   from HTML/MathML/ISO sets). Controlled by `entity_load_mode` config.

None of these require DTD. They are model-level knowledge in the EntityRegistry.

### DTD-Declared Entities (Future)

Strict mode's full value requires parsing DTD entity declarations from
`<!DOCTYPE ... [ <!ENTITY name "value"> ]>`. This is a separate feature
(external to this TODO). Until then, strict mode behaves like lenient mode.

## Files to Modify

- `lib/moxml/config.rb` — add `entity_restoration_mode` attribute
- `lib/moxml/entity_registry.rb` — add `should_restore?`, `standard_entity?`
- `lib/moxml/document_builder.rb` — use `should_restore?` from registry (ties into TODO 2)

## Dependencies

- TODO 2 (model-driven restoration) should be done first so the policy is
  centralized in EntityRegistry
- TODO 1 (adapter support) should be done first so entities can actually be created
