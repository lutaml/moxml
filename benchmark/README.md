# Performance scoreboard

`benchmark/scoreboard.rb` is the published performance surface
(TODO.sota/04). It answers one question for every operation a
consumer runs: **how does moxml on its fastest engine lane compare
with raw nokogiri on the same operation?**

## Protocol

- **CPU time medians** (`CLOCK_PROCESS_CPUTIME_ID`), not wall time —
  scheduler noise never becomes a performance claim.
- **Interleaved A/B**: baseline and candidate alternate every
  repetition in the same thermal window; warmups are discarded and
  GC runs between samples. The ratio is `median(baseline) /
  median(candidate)`; `> 1.0x` means moxml is faster.
- **Load gate**: the harness refuses to report when the 1-minute
  load exceeds half the CPU count. `SCORE_FORCE=1` overrides for
  smoke runs only — such numbers are not publishable.
- Rows name the exact operation measured; lazy and materialized
  XPath results are separate rows because they cost different things.
- The pair is **moxml + leptris latest**; the baseline is raw
  nokogiri on the same document.

## Rows

| Row | Operation | Kind |
| --- | --------- | ---- |
| `parse` | `Nokogiri::XML` vs `ctx.parse` on the catalog document | parity |
| `serialize` | `doc.to_xml` | parity |
| `xpath //field (count)` | node-set cardinality, nothing materialized | parity |
| `xpath //field (each)` | iterate every result (wrapper materialization) | structural |
| `attr pairs listing` | collect `[name, value]` for every record | parity |
| `build add_element` | create + attach 300 records x 4 fields with attrs and text | structural |
| `walk+read (warm)` | traverse a pre-parsed document, read name + text | structural |
| `walk+read (cold)` | parse + the same traversal | structural |
| `children recursion (cold)` | parse + recurse via `children` filtering elements | structural |
| `plan records (typed)` | compiled `Moxml::Plan` vs the hand-written typed walk | data API |

**Parity rows** are the commitment: the lock fails below a 0.95
measurement floor. **Structural rows** are measured and trend-locked
(no row may regress >10% against the committed baseline), but they
are known to be below parity — the gaps are listed below. **Data
API** rows are informational: they show what consumers gain by using
the record APIs instead of node-by-node access.

## Commands

```bash
# Every row, human-readable
bundle exec rake benchmark:scoreboard

# One or more rows
SCORE_ROWS="parse,serialize" bundle exec ruby benchmark/scoreboard.rb

# Another engine lane
SCORE_ADAPTER=oga bundle exec ruby benchmark/scoreboard.rb

# Machine-readable results (protocol metadata + rows)
SCORE_JSON=benchmark/scoreboard.json bundle exec ruby benchmark/scoreboard.rb

# CI lock: parity rows >= 1.0x, and no row > 10% below the baseline
SCORE_LOCK=1 SCORE_BASELINE=benchmark/scoreboard.json \
  bundle exec ruby benchmark/scoreboard.rb
```

Rows with a tracked upstream regression are logged as paused and do not
fail the lock (`KNOWN_REGRESSIONS` in `scoreboard.rb`); they stay
measured and published, and the entry is removed when its issue lands.
The current entries are the two cold crossing-bound walk rows
(`walk+read (cold)`, `children recursion (cold)`) under
leptris-ruby#527 (the per-element crossings of the 1.9.380+ line —
facade-side, not evaluator-side: the engine's own eval and walk
measured flat across 1.9.374→1.9.380). `walk+read (warm)` recovered
above parity (1.15-1.17x on the release runs) and left the pause
list — a future dip now fails the lock again. The count row's
0.70x reading that opened #527 was the adapter minting every row
before the caller asked (fixed by the deferred bulk mint); it
measures 3.50x on the released tree and is promoted back to a
parity row.

A smoke run on a loaded machine:

```bash
SCORE_FORCE=1 SCORE_REPS=5 bundle exec ruby benchmark/scoreboard.rb
```

## Honest status

Reference run (generated; do not edit by hand — `SCORE_PUBLISH=1`
rewrites this block and `docs/_pages/performance.adoc`):

<!-- SCOREBOARD:BEGIN -->
| Row | Ratio | Kind | Status |
| --- | ----- | ---- | ------ |
| `parse` | 4.62x | parity | met |
| `serialize` | 1.72x | parity | met |
| `xpath //field (count)` | 0.70x | structural | tracked (below parity) |
| `xpath //field (each)` | 0.36x | structural | tracked (below parity) |
| `attr pairs listing` | 7.92x | parity | met |
| `build add_element` | 0.60x | structural | tracked (below parity) |
| `walk+read (warm)` | 0.54x | structural | tracked (below parity) |
| `walk+read (cold)` | 0.21x | structural | tracked (below parity) |
| `children recursion (cold)` | 0.18x | structural | tracked (below parity) |
| `plan records (typed)` | 1.13x | data | informational |
<!-- SCOREBOARD:END -->

The open rows are the known structural gap: every node the facade
hands a consumer is a contract-carrying wrapper with its own
identity/invalidation state, while nokogiri hands out thin handles.
Closing them needs engine-side construction/walk faces (leptris
C contract work), not more facade tuning. Facade-side wins already
landed here: single-crossing `add_element` construction, native
`set_binding_text` without a binding-twin mint per write, and the
generation memo no longer writing on every `children` read.

Numbers move by a few percent between runs; the lock's 10% tolerance
is the regression tripwire, not a claim of precision. The committed
baseline is a reference measured on a shared machine — regenerate it
on a quiet machine (the `performance` workflow uploads its measured
`scoreboard.json` as an artifact) before treating a lock failure as
a regression.
