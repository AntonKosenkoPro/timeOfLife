## 1. Red tests (write first, all must fail before the fix)

- [x] 1.1 Keep `RoundTripReproTests.roundTripsDoNotDuplicateEntries` (A→B→A→B, currently failing 1→2→3) as the prevention red test; extend it to also assert relay-side generation counts stay at 1 per account.
- [x] 1.2 LocalStoreTests: adoption/heal writes `adoption_map` rows (old→new per resource) in the same transaction; transitive resolution (O→F→G) returns the live id; mappings survive the rows they describe being clean across switches.
- [x] 1.3 SyncControllerTests: pull of a mapped-but-locally-unknown entry id merges onto the live row (LWW) with no new row and no outbox row; pull of a mapped id whose live row is locally deleted stays skipped; pull of an unmapped unknown id still inserts (existing behavior pinned).
- [x] 1.4 LocalStoreTests: convergence folds byte-identical groups to the intact-refs survivor (relay deletes enqueued); divergent groups, rows with outbox rows, buffered rows, and locally-deleted rows are untouched.

## 2. Prevention: adoption map + map-aware pull (LocalStore stays the single chokepoint)

- [x] 2.1 LocalStore: additive `adoption_map(old_id, new_id, resource)` table; write rows in adoption and both heal helpers; transitive resolve helper; drop map rows with the row on local delete.
- [x] 2.2 SyncController: pull entry/category merge resolves unknown ids through the map before insert (merge-onto-live under LWW, existing category-join rules, delete-wins preserved).
- [x] 2.3 `swiftlint lint --strict` clean; `xcodebuild` build warning-free; full suite green with 1.x now passing (incl. the round-trip repro at ×1).

## 3. Cure: one-time convergence + prod cleanup verification

- [x] 3.1 LocalStore: one-time convergence op (byte-identical groups only, intact-refs survivor, hard-delete losers locally + enqueue relay deletes, once-flag in local metadata, runs before the first post-update cycle).
- [x] 3.2 Verification: scripted 1→2→3 fixture converged to ×1 locally; relay-side Loser deletes drain as tombstones; divergent-edit fixture keeps both copies; FURPS Timetracking (F8/F11/F15) and `docs/project-context.md` sync plane updated.
- [ ] 3.3 Live confirmation (read-only relay checks): SiWA account back to 26 entries / OTP account back to 26, categories still 10 unique each; device History shows no triples.

## 4. Summary and archive offer

- [ ] 4.1 Summarize evidence → fix → verification for the human and offer `openspec archive fix-round-trip-duplication` (do not archive unasked).
