## 1. Backend contract and storage

- [x] 1.1Update `backend/api/openapi.yaml`: entries gain `activity_text`/`category_ids`/`notes`, drop `activity_id` FK semantics and `/activities*` routes, re-point entry category filter through `entry_categories`
- [x] 1.2Add migration: `entries.activity_text` + `notes`, `entry_categories(entry_id, category_id, position)`, backfill from activities + joins, drop `activities`/`activity_categories`
- [x] 1.3Update `Store` interface + sqlite/postgres impls: entry CRUD with owned fields, `entry_categories` writes, recents query (`GROUP BY activity_text_exact`, newest wins, limit 6), drop activity methods
- [x] 1.4Update catalog validators: entry text (trimmed non-empty, 60 chars), notes (280 runes), ordered category ids; remove activity validators

## 2. Backend handlers and tests

- [x] 2.1Rewrite entries handlers for the new payload; remove activities handlers/routes; prune-unknown-category on merge
- [x] 2.2Update backend tests (catalog/entries/deletions/contract): cascade-removal, per-entry isolation, exact identity (`Gym` ≠ `GYM`), prune rule, tombstones entries-only
- [x] 2.3Run `go build ./...`, `go test ./... -cover`, `golangci-lint run`, `gofmt -l .` (empty), `go vet ./...`

## 3. iOS store and migration

- [x] 3.1`LocalStore` v2 migration: entries own text/cats/notes, `entry_categories(position)`, transposed `timer_state(text, category_ids, started_at, status)`; backfill + drop old tables; keep chokepoint (no raw GRDB writes outside)
- [x] 3.2Rewrite store queries: entries with own categories, recents query with `(user_id, activity_text, started_at)` index, delete `createOrResolveActivity`/`remapActivityReferences`/pending-deletion restore/activity snapshots
- [x] 3.3Update `CatalogModels` (`TimeEntry` owns text/cats/notes; delete `Activity` record type or repurpose as text draft), `ActivityName` exact-trim rule

## 4. iOS Track, entry form, History, Insights

- [x] 4.1Track: plain-text name field + 6 exact recents chips (first-category icon) + Start gate; delete search sheet/`ActivitySearchResults`/quick-create; `TrackState` keyed on text draft
- [x] 4.2Running timer: locked name + shared ordered `TagSelector` (select-only, zero allowed); toggles rewrite draft snapshot; Stop creates entry + single outbox row
- [x] 4.3Entry form (`LogTimeViewModel` + view): Name + Categories + Notes + Starts/Ends, new validity gate, no `store.activity(id:)` re-resolve; EDIT/LOCKED prefill from entry fields
- [x] 4.4History: rows read entry-owned categories; tap opens entry form cover directly; delete `ActivityDetailView`/VM/route; keep day groups, totals, `[+]`, invalidate/reload
- [x] 4.5Insights: activity lens groups by exact text, category lens attributes from entry cats; keep full-credit footnote; delete `ActivityEditorView`, Profile activity-management copy
- [x] 4.6Compact timer + AppShell settle copy follow text draft (no `activityID` keys)

## 5. Sync client

- [x] 5.1Entries-only payload (`activity_text`, ordered `category_ids`, `notes`); drop activity pull/merge/remap/parent-heal; prune-unknown-category; in-progress drafts never enter outbox
- [x] 5.2Tombstones entries/categories only (entry joins cascade); delete-wins scoped to entries/categories; cursors per remaining resource
- [x] 5.3Update sync tests: single-create-at-Stop, prune rule, no-churn-on-toggle, cascade joins, R1 recreation

## 6. Strings, theme, cleanup

- [x] 6.1EN + RU strings + `L10n` for new copy (plain-text prompts, running tags, entry form rows); remove activity-catalog strings; `Theme` colors only
- [x] 6.2Remove dead code: search/sheet components, `ActivityEditor`, activity undo snapshots, `activity_exists`/`activity_not_found` handling, stale icons/copy
- [x] 6.3 Re-check `Requirements/FURPS/Activity_Catalog_and_Categories.md` + `Timetracking.md` rows; resolve conflicts

## 7. Verification and docs

- [x] 7.1iOS: `swiftlint lint --strict`, `xcodebuild -scheme TimeOfLife -destination 'generic/platform=iOS Simulator' build`, `xcodebuild test -scheme TimeOfLife`
- [x] 7.2Backend: repeat 2.3 green (build, tests-cover, golangci-lint, gofmt empty, vet)
- [x] 7.3 Update `docs/project-context.md` (data plane, timer, history, sync, incomplete/deferred), `README.md`/`AGENTS.md` pointers, `Design/DECISIONS.md` (D20/D24 reversal), `Design/SCREENS/*` (TimeTracking, entry form, History, Insights), `Requirements/FURPS/*` rows
- [x] 7.4 Run `openspec validate --all` green
