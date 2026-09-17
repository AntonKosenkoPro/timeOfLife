# Tasks: drain-404-convergence

## 1. Push-404 convergence (SyncController, no schema/contract change)

- [x] 1.1 Drain catch: entry create/update + `activity_not_found`/`not_found` → tombstone-equivalent converge + continue; activity/category update + `not_found` → same; DELETE + any 404 → success; activity/category create + 404 → still throws.
- [x] 1.2 `applyTombstones`: `not_found` from `fetchDeletions` → log + skip (stateless pre-tombstone tolerance); all other errors still throw.
- [x] 1.3 `MockCatalogRepository.fetchDeletionsHandler` (throwing variant, mirrors other handlers).
- [x] 1.4 Tests: entry-create→`activity_not_found` converges (no DELETE pushed, idle); entry-update→`not_found`; activity-update→`not_found` (cascade + entry rows dropped); category-update→`not_found`; fetchDeletions→`not_found` runs drain+pull to idle; activity-create→`not_found` still throws.

## 2. Stop on deleted activity (TimerService + Track, one L10n key)

- [x] 2.1 `TimerService.stopTimer`: clear timer state before saving; missing activity → skip entry + throw typed `activityDeleted`.
- [x] 2.2 `TrackViewModel.stop()`: map `activityDeleted` → `.idle` + `timer.activityDeleted` message (no ticker restart, no retry); other errors keep the recoverable path.
- [x] 2.3 L10n `timer.activityDeleted` EN+RU + case (U4, LocalizationTests parity + count 177).
- [x] 2.4 Tests: stop on missing activity clears state/saves nothing/throws typed; Track settles idle with message.

## 3. Verification and docs

- [x] 3.1 `swiftlint lint --strict` clean; warning-free build; full `xcodebuild test` green — 551/551 (one transient load-flake in an untouched timing-sensitive editor test on the first full pass; green in isolation and on re-run).
- [x] 3.2 FURPS F14 gains the convergence clause; `docs/project-context.md` sync-plane line; no OpenAPI/backend changes.
- [x] 3.3 `openspec validate --all` green; archive (folds into `sync-client` + `timer-capture-experience` baselines).
