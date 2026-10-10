## 1. Reproduction (repo rule S5 — no fix without a recorded repro)

- [x] 1.1 Seed 120 entries on the relay (SQLite-backed test harness or local server), run a fresh sign-in + first sync, and record the local row count — expect 50 (truncation confirmed on the current tree)
- [x] 1.2 Record the same repro for a delta pull: advance past the truncated cursor, add an older-`started_at` entry with small `updated_at` on the relay, sync, confirm it never arrives

## 2. iOS relay client paging

- [x] 2.1 Decode optional `next_cursor` on `EntryListResponse` (absent = last page; in place, no legacy branches)
- [x] 2.2 Loop `fetchEntries` over `cursor` pages with explicit `limit=200` until the relay returns no cursor; return the concatenated entries
- [x] 2.3 Extend `RemoteCatalogRepositoryTests` with multi-page decoding (page 1 + cursor → page 2, no cursor) and empty-last-page cases

## 3. SyncController pull convergence

- [x] 3.1 Merge every received page with the existing LWW / category-resolution rules; check the same-account guard after each page fetch before merging it
- [x] 3.2 Advance the `entry` cursor once per pull to the max `updated_at` over all merged pages; leave the cursor unchanged when the pull merged nothing
- [x] 3.3 Add `SyncControllerTests` regression: 120-entry relay over default pages converges fully, cursor equals the global max, and the follow-up delta is empty

## 4. Contract + docs touch-up

- [x] 4.1 Clarify in `backend/api/openapi.yaml` (`GET /entries`) that sync clients must exhaust `next_cursor` pages and advance their cursor over the complete result (no endpoint change)
- [x] 4.2 Re-check the relevant `Requirements/FURPS/*.md` rows for conflicts and fix as needed

## 5. Verification (S5)

- [x] 5.1 Re-run the 1.1/1.2 repros on the fixed tree and record full convergence (120/120 rows; late older entry arrives)
- [x] 5.2 Backend green: `gofmt -l .` empty, `go vet ./...`, `golangci-lint run`, `go test ./... -cover`
- [x] 5.3 iOS green: `swiftlint lint --strict`, warning-clean `xcodebuild` build, `xcodebuild test` suite green
- [x] 5.4 `openspec validate --all --strict` green on the change
