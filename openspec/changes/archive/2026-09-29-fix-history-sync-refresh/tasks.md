## 1. Sync-completion refresh

- [x] 1.1 Observe `SyncController.status` in `HistoryView` (direct `@EnvironmentObject`, ProfileView precedent); on exit from `.syncing` call `vm.invalidate()` + `loadIfNeeded()`
- [x] 1.2 Apply the same status-observed invalidate + reload in `InsightsView` / `InsightsViewModel`
- [x] 1.3 Verify Profile-sheet Sync now over History and over Insights shows pulled entries/deletions with no tab switch (manual QA on simulator, incl. auto foreground/connectivity trigger while visible)

## 2. Tests

- [x] 2.1 Add/extend `HistoryViewModelTests` for reload-after-sync (pulled entry appears, tombstoned entry disappears, day group removed when empty)
- [x] 2.2 Add/extend `InsightsViewModelTests` for breakdown recompute after sync merge
- [x] 2.3 Run `xcodebuild test -scheme TimeOfLife` green; no new warnings (warnings are errors via `project.yml`)

## 3. Linters, requirements, docs

- [x] 3.1 Run `swiftlint lint --strict` (from `ios/TimeOfLife/`) and fix every finding
- [x] 3.2 Re-check `Requirements/FURPS/*.md` rows for History/sync; fix conflicts
- [x] 3.3 Update `docs/project-context.md` if lifecycle/contract notes changed; no OpenAPI/backend changes expected
