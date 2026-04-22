# TODO.remaining — Consolidated Action Items

Consolidated from: TODO.entities-work.md, TODO.entity-support.md,
TODO.full-entity.md, TODO.full-entity-support.md, TODO.entity-handling.md,
TODO.mn-bilingual-round-trip.md, plus code audit (2026-04-22).

Those root files are superseded and can be removed.

## Dependency Order

```
TODO 1 (Adapter Support)
   |
   v
TODO 2 (Model-Driven Restoration) ---> TODO 4 (Lenient Entities Mode)
   |
   v
TODO 3 (Test Coverage)

TODO 5 (Fixture Integrity) — independent
TODO 6 (Ox Element Ordering) — independent
TODO 7 (HeadedOx Limitations) — independent
TODO 8 (XPath Predicate Gaps) — independent
TODO 9 (Cleanup Hygiene) — independent
```

## Summary

| # | File | Description | Status |
|---|------|-------------|--------|
| 1 | `1-entity-reference-adapter-support.md` | EntityReference in Ox, Oga, REXML, LibXML, HeadedOx | Done |
| 2 | `2-entity-restoration-model-driven.md` | Use EntityRegistry as source of truth for restoration | Done |
| 3 | `3-entity-reference-test-coverage.md` | Tests for EntityReference nodes and round-trips | Done |
| 4 | `4-lenient-entities-mode.md` | Strict vs lenient entity restoration mode | Done |
| 5 | `5-fixture-integrity.md` | Bilingual fixture verification + CI validation | Done |
| 6 | `6-ox-element-ordering-bug.md` | Ox adapter reorders elements in certain fixtures | Done |
| 7 | `7-headed-ox-limitations.md` | 15 skipped tests across 7 HeadedOx limitation areas | Partial (7c,7d,7g done; 7a done; 7b,7e blocked by Ox gem; 7f blocked by 7b) |
| 8 | `8-xpath-predicate-gaps.md` | position()/last()/id() not working in XPath predicates | Done |
| 9 | `9-cleanup-hygiene.md` | Stale doc links, untracked scripts, superseded files | Done |

## What's Already Done

- EntityReference node class (`lib/moxml/entity_reference.rb`)
- EntityRegistry with 2125 W3C entities (`lib/moxml/entity_registry.rb`)
- Node type registry includes `:entity_reference`
- Base adapter template: `create_entity_reference`, `validate_entity_reference_name`
- Nokogiri adapter: full native EntityReference support
- Document factory: `create_entity_reference(name)`
- DocumentBuilder: `visit_entity_reference` + partial `restore_entities_in_text`
- Builder DSL: `entity_reference(name)`
- Config: `restore_entities`, `entity_load_mode`, `entity_provider`, `preload_entity_sets`
- Context: entity registry integration
- EntityRegistry tests (24 examples passing)
- HeadedOx limitations documented in `docs/_pages/headed-ox-limitations.adoc`
