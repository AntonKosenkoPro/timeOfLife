## Why

Signing out and back in across accounts (OTP → SiWA → OTP → SiWA, e.g. after
revoking the Apple authorization in Settings) silently triplicates every entry:
prod relay holds 26 logical entries as 78 rows on the SiWA account (created in
three per-switch clusters: 7 + 19 + 52) and 52 on the OTP account, with all
sync cycles green. Each account round trip with a drain in between adds one
full generation on each side — a duplication engine, not a one-off glitch.
Reproduced in isolation: scripted A→B→A→B round trips with drains grow 1 → 2 →
3 local rows per logical entry (`RoundTripReproTests`, currently failing).

## What Changes

- **Stop the bleeding (prevention):** `LocalStore` records every adoption/heal
  id rewrite in a persistent `adoption_map(old_id → new_id)` (single chokepoint,
  exact id chains — no content heuristics, so no false-merge risk). The pull
  merge resolves relay ids through the map (transitively): a server id that is
  a superseded generation merges onto the live local row (LWW) instead of being
  inserted as a new row. Applies to entries and categories. Pre-fix generations
  (rewritten before any map existed) fall back to a byte-identical live row —
  but collapse and retirement still require the live row to be rewrite-minted,
  so history-less rows are never folded by content.
- **Clean up the existing generations (cure):** a one-time convergence folds
  same-account entries with byte-identical business payloads (text, notes,
  timing, category set, provenance) down to one survivor — the generation with
  intact category references — deleting the rest locally and on the relay via
  the existing hard-delete → tombstone machinery (so other devices converge).
  Groups with divergent payloads (user edited a copy) are kept whole, never
  auto-merged. Runs once, converges through normal sync; categories need no
  action (same-name remap already collapsed them — verified: 10 unique names).
- No relay deploy, no schema change, no new error codes, no identity merging.

## Capabilities

### New Capabilities

(none — all behavior attaches to existing capabilities)

### Modified Capabilities

- `sync-client`: pull merge recognizes superseded generations via the adoption
  map (merge-onto-live instead of insert-as-new); adoption-triggered cycles
  unchanged otherwise.
- `local-first-store`: adoption/heal writes map rows in the chokepoint
  transaction; one-time duplicate convergence (byte-identical groups only,
  delete-wins and outbox/undo guards respected).

## Impact

- iOS: `LocalStore` (new `adoption_map` table, map-aware adoption/heal,
  converge-duplicates op), `SyncController` (pull resolution through the map),
  `SyncControllerTests`/`LocalStoreTests` (red-first: the repro test plus map
  and convergence tests). The scratch `RoundTripReproTests` becomes the
  red test for prevention.
- Backend: none (local-only fix; relay cleanup rides existing tombstones).
- Non-goals: OTP↔SiWA identity merging; fuzzy/content-similarity matching;
  auto-merging divergent copies; touching tombstone/delete-wins semantics.
