# TODO 9: Cleanup and Hygiene

Small items that don't affect functionality but should be addressed.

## 9a. Stale Doc Links in Skip Messages

15+ test skip messages reference `docs/HEADED_OX_LIMITATIONS.md` but the
actual file is at `docs/_pages/headed-ox-limitations.adoc`. The referenced
path does not exist.

**Fix:** Update all skip messages to reference
`docs/_pages/headed-ox-limitations.adoc` instead.

**Affected files:**
- `spec/integration/headed_ox_integration_spec.rb`
- `spec/integration/shared_examples/integration_workflows.rb`
- `spec/integration/shared_examples/node_wrappers/node_behavior.rb`
- `spec/integration/shared_examples/node_wrappers/cdata_behavior.rb`
- `spec/integration/shared_examples/edge_cases.rb`
- `spec/moxml/xpath/axes_spec.rb`
- `spec/moxml/xpath/compiler_spec.rb`
- `spec/moxml/adapter/headed_ox_spec.rb`

## 9b. Untracked `scripts/` Directory

`scripts/format_xml.rb` and `scripts/pretty_format_xml.rb` exist as untracked
files. Decide whether to commit (and add to `.gitignore` pattern or document)
or remove.

## 9c. Superseded Root TODO Files

The following root-level files are marked as superseded in
`TODO.remaining/README.md` but still exist:

- `TODO.entities-work.md`
- `TODO.entity-handling.md`
- `TODO.entity-support.md`
- `TODO.full-entity-support.md`
- `TODO.full-entity.md`
- `TODO.mn-bilingual-round-trip.md`

Once all work is confirmed tracked in `TODO.remaining/`, these can be deleted.
