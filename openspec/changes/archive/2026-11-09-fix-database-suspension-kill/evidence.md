# Crash and verification evidence

## Original incident (confirmed, not a local reproduction)

- Incident: `15DCF143-C36B-43C9-8BBB-C4F8EFCA7A17`.
- Timestamp: `2026-11-09 09:26:28.3090 +0200`; launch `08:07:22.0999 +0200`.
- TestFlight `TimeOfLife`, bundle `com.antonkosenko.timeoflifeapp`, version `0.2.8 (153)`.
- Hardware `iPhone18,3`; OS `27.2 (24B119)`.
- Exception `EXC_CRASH (SIGKILL)`; termination `RUNNINGBOARD 0xdead10cc`.
- Source: local Xcode Products crash point `2SdAqenz-eCKdwDZeULO.xccrashpoint`, log `2026-11-09_09-26-28.3090_+0200-bfc43cf83ff5ad4636f8cf9cb321fc0267bf3e42.crash` (LocallySymbolicated and raw copies).
- Thread 0 frames 0–7: idle `mach_msg2_trap` / CoreFoundation run-loop wait. The screenshot's SwiftUI `withMemoryRebound` at frame 11 is below `UIApplicationMain`, not a faulting pointer operation.
- Thread 11: category date decoding / active GRDB cursor → `DatabaseQueue.read` → `LocalStore.categories` → `TimerService.loadSnapshot` → `TrackViewModel.load`.
- Three build-152 reports in the same crash point, Oct 29–30, share `0xdead10cc`.

Apple's SIGKILL reference states that this code means a file or SQLite lock was held during suspension: https://developer.apple.com/documentation/xcode/sigkill . It is distinct from the responsiveness-watchdog code `0x8badf00d`. The report does not identify the exact reload trigger, show that the query was blocked, or prove memory pressure or SwiftUI corruption.

## Current-tree reproduction gate

The iOS worker recorded the failing regression before production edits: `LocalStoreSuspensionTests` ran three tests with two failures (`suspendedStoreRefusesLockAcquisition`, `openWhileSuspendedRefusesAccess`); the real file-backed production queue still accepted reads/opening after the suspension signal. See repro.md for commands and red log names. This reproduces the unsafe access condition, not a physical-device RunningBoard SIGKILL.

## Post-fix automated verification

- The identical red cases now pass; final filtered coverage after review fixes: **23 tests in 5 suites passed** (`green2-test.log`).
- Final full iOS suite: **1074 tests in 103 suites passed** (`full2-test.log`); strict SwiftLint: 0 violations in 263 files; app/test build passed (pre-existing AppIntents metadata-extraction warnings remain).
- An intermediate test caught a stranded `.syncing` status on suspension; the cycle now parks and resumes without a user-facing sync error.
- Pinned GRDB 7.8.0 research, signal semantics and exact test/log references: research.md and repro.md.
- Limitation: active-query interruption/rollback is source-verified structurally, not reproduced deterministically through the public LocalStore API. Refusal of new access, state preservation, resumption and lifecycle recovery have executable regression coverage.

## Review follow-up

An independent app/sync review identified three actionable recovery gaps after the initial green suite: activate-started sync parked in an untriggerable `.inactive` state; raw GRDB interruption was classified using a live flag that could clear before the catch; manual sync lacked the trigger's suspension guard. These were corrected with a production `SyncController.resume` entry point, stable interruption classification, and a manual-sync guard. See repro.md R1–R3 for red/green evidence (the manual guard's behavior test already passed before that guard; no fabricated red claim).

The storage review additionally found that a redundant same-account open during suspension could run the catch-all failed-binding cleanup, dropping a healthy binding. Dedicated red/green regressions now cover idempotent same-account handling and fail-safe refused switching. Test cleanup is guaranteed by conditional defers; a temporary serial-runner probe confirmed sequential suite execution in the verified scheme. Per-suite serialization alone does not prove cross-suite isolation; enabling parallel suite execution requires revisiting these process-global-state tests.

A concurrency follow-up found that generation checks alone did not order GRDB notification effects: an expiry could release the state lock, be overtaken by foreground resume, then post stale suspension last. Mutation plus GRDB-post ordering is now serialized as a unit; the 50-round stress test observed real flag/queue disagreement before the fix and passes after. This is executable evidence plus a structural ordering guarantee, not proof of absence from stress alone. Background cleanup uses `resumeForBackgroundTask`, which does not emit foreground app-level notifications or initiate unrelated sync/binding/reloads. See repro.md R5–R6.

The suggestion to silently swallow suspension failures in user-initiated Stop/undo mutations was not accepted as an automatic load-style rule: `timer-capture-experience` → "Save failure" explicitly requires recoverable running state plus a localized non-field error when storage cannot save. Suppressing that error without retrying the actual mutation would silently drop user intent. No data-loss or missing retry path was demonstrated for these existing mutation handlers.

Both independent reviewers re-read the final fixes and confirmed no remaining concrete blocker in their reviewed scope. The owned test simulator was shut down after final verification; no Argent session or other simulator was touched. No commits, pushes, PR, release, or baseline-spec archival was performed.

## Backend baseline verification

At `986db127`, unchanged `backend/`: `gofmt -l .` empty; `go vet ./...`, `go build ./...`, `golangci-lint run` (0 issues), and `go test ./... -cover` all passed on 2026-11-09. No backend edits.

## Physical-device follow-up

Not run. The exact OS-enforced kill and its absence after the fix require a real-device smoke check; deterministic regression tests must not be presented as that check.
