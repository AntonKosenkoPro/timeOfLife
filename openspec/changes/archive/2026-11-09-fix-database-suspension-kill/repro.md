# Reproduction — fix-database-suspension-kill (iOS worker)

## What was reproduced (and what was not)

Reproduced on the base tree: **a bound `LocalStore` backed by a real temporary-file GRDB queue keeps acquiring database access across the production suspension-signal path** — reads succeed after `Database.suspendNotification`, and a store opened while suspended migrates and reads normally. That is the unsafe condition the 0xdead10cc termination punishes (held file/SQLite lock at suspension).

NOT reproduced: a physical-device RunningBoard SIGKILL. The simulator cannot enforce suspension kills; these tests drive the production `NotificationCenter` + production `DatabaseQueue` path with actual GRDB and assert fail-fast-vs-lock-acquisition behavior. Simulated lifecycle is labeled as such in every test header.

## Red-run evidence (base tree, before production edits)

Suite: `TimeOfLifeTests/LocalStoreSuspensionTests` (new file `ios/TimeOfLife/TimeOfLifeTests/LocalStoreSuspensionTests.swift`).

- Build: `xcodebuild build-for-testing -scheme TimeOfLife -destination "platform=iOS Simulator,id=6CD4BAE5-2EA1-47D2-BE91-36026AC167B5" -derivedDataPath "/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/lifio-dd-suspension"` → `TEST BUILD SUCCEEDED` (`EXIT=0`).
  Log: `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/suspension-build2.log` (exit: `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/suspension-build2.done`).
- Test: same destination/derived-data + `-only-testing:TimeOfLifeTests/LocalStoreSuspensionTests` → `TEST EXECUTE FAILED`, `EXIT=65`, 3 tests / 2 issues in 0.031s.
  Log: `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/suspension-test2.log` (exit: `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/suspension-test2.done`):
  - `suspendedStoreRefusesLockAcquisition` — **RED** (`Issue.record` at `LocalStoreSuspensionTests.swift:47`): `store.categories()` succeeded while suspended; no `SQLITE_ABORT`/`SQLITE_INTERRUPT`.
  - `openWhileSuspendedRefusesAccess` — **RED** (`Issue.record` at `LocalStoreSuspensionTests.swift:89`): open migrated and reads succeeded while suspended.
  - `resumeRestoresAccess` — **GREEN** (guard against a fix that suspends permanently).
- Earlier superseded red-run pair (2-test suite, same verdict): build `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/suspension-build.log`, test `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/suspension-test.log`.
- Simulator: was booted `iPhone 18 Pro Max` (`6CD4BAE5-2EA1-47D2-BE91-36026AC167B5`, iOS 27.2 runtime family — closest available to the incident's iPhone18,3 / iOS 27.2); shut down after final verification (cleanup confirmed `Shutdown`, no other simulator/process touched).

## Coverage limits (truthful gaps)

- **In-flight interruption is not unit-deterministic through the public API.** Every `LocalStore` operation is a short synchronous GRDB call; there is no injectable long statement, and test-only suspend hooks are forbidden (they would not exercise the production path). Interruption is therefore covered structurally, not by a red test: the suspend post runs synchronously on the posting thread into `sqlite3_interrupt` (pinned-source verified), and the BG expiry path posts before completing the task. The deterministic suite covers fail-fast of new work, open-while-suspended inheritance, no-partial-state on refused writes, and resume/repeat behavior.
- **Real-device kill/absence-of-kill** remains a manual smoke item (main owns the checklist); these automated checks must not be presented as that check.

## Post-fix verification (implementation complete)

- Filtered run (same destination/derived-data, `build-for-testing` + `test-without-building` with `-only-testing` for the four suspension suites): **15 tests in 4 suites passed in 0.374s** (`EXIT=0`).
  Logs: `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/fix-build.log` (exit: `…/fix-build.done`), `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/fix-test.log` (exit: `…/fix-test.done`) — the two red repro tests now pass, plus 13 new regression tests (refused-write-no-partial-state, account-switch isolation, repeat cycles, generation guard, classification, 4 reload-keeps-snapshot, reap-ends-nothing, trigger-refused, abort-silent-then-recover).
- Intermediate signal: the first post-fix run caught a real bug the new tests were built to catch — `finishSuspendedCycle` restored entry status `.syncing` for activate-started cycles, stranding "syncing" forever (visible in `fix-test.log` 18:22 run, `isIdle` false). Fixed to park `.inactive` for the self-started case; re-run green.
- Full suite: **1066 tests in 102 suites passed in 19.864s** (`EXIT=0`), no regressions.
  Log: `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/full-test.log` (exit: `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/full-test.done`).
- `swiftlint lint --strict` (from `ios/TimeOfLife/`): 0 violations in 262 files. No log file — output went to the invoking terminal; command and clean result recorded here instead.
- Build warning-clean (app/test targets are warnings-as-errors; only the pre-existing AppIntents metadata note remains in `fix-build.log`).
- Coverage limits from the red section still hold: no physical-device kill check (owner's smoke checklist), in-flight interruption covered structurally (see below, retained verbatim).
- Generated-file note: `xcodegen generate` was re-run after adding `DatabaseSuspension.swift` + the two test files so they join their targets. `project.pbxproj` is gitignored (generated, untracked) — no repo diff. `Package.resolved` is tracked and **unchanged** (`git diff` empty for it): no version resolution occurred, GRDB stays pinned at 7.8.0.

## Second round — independent review findings (all reproduced red, fixed, re-verified)

Independent storage/BG + UI/sync reviewers proved four further defects on the phase-one tree. Each was reproduced red on the then-current tree before its fix; red and green logs below.

- Red batch build: `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/red2-build.log` (`EXIT=0`).
- Red batch test: `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/red2-test.log` (`EXIT=65`, 21 tests in 6 suites, 8 issues). One run stalled pre-start at "Resolve Package Graph" with zero tests executing (environmental; sampled the idle host, killed, retried once per the repo loop — retry ran clean).
- Green batch build: `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/green2-build.log` (`EXIT=0`, warning-clean).
- Green batch test: `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/green2-test.log` (`EXIT=0`, **23 tests in 5 suites passed in 0.729s**).
- Final full suite: `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/full2-test.log` (`EXIT=0`, **1074 tests in 103 suites passed in 19.564s**). Final `swiftlint lint --strict`: 0 violations in 263 files (terminal output, no log file).

### R1 — stranded sync after suspension-abort (UI/sync reviewer, CRITICAL)

Shape: `finishSuspendedCycle` parked `.inactive` for activate-started cycles, and the production did-resume path only called `trigger` (refused while `.inactive`) — sync stranded dead with a full outbox; the pre-existing recovery test masked it with a direct second `activate`, unlike production.
Red: `SyncControllerSuspensionTests.productionResumeTriggerConvergesAfterAbort` drove activate-while-suspended → abort → resume → production `trigger`, asserting idle + drained outbox — **RED** (status stuck non-idle, outbox full).
Fix: new `SyncController.resume(userID:)` (activate-if-inactive else trigger; idempotent, same-account guarded) adopted by all three RootView foreground entry points (restore task, connectivity flip, will-enter-foreground) plus the did-resume handler; test switched to the production `resume()` entry point — green. No cross-account regression: `activate` deactivates first on user mismatch; `trigger` keeps its bound/fence guards.

### R2 — suspension classification TOCTOU (UI/sync reviewer)

Shape: `isSuspensionError` corroborated raw `SQLITE_ABORT`/`SQLITE_INTERRUPT` against live `isSuspended`, so a resume landing between the throw and the catch (they straddle an await hop) flipped a genuine refusal into a permanent error.
Red: `DatabaseSuspensionTests.suspensionErrorsClassifyAfterResume` classified both codes after an explicit resume — **RED** on the old corroborated check, green after making the codes unconditional (documented: pinned 7.8.0 produces ABORT only for suspension-abort — no `ON CONFLICT ROLLBACK` clauses in the schema — and INTERRUPT only via `sqlite3_interrupt`; task cancellation surfaces as `CancellationError`, which GRDB prioritizes). Plus a scheduling-robustness test (`resumeRacingRefusalStaysSafe`) that passes on both trees by construction and locks the safe outcome. No message matching added.

### R3 — `syncNow` lacked the suspension guard (UI/sync reviewer)

Fix: same `isSuspended` early-return as `trigger`; manual error semantics preserved for genuine failures (guard only refuses while suspended; resume owns the retry). Test `syncNowWhileSuspendedStartsNoCycle` locks status-unchanged + zero remote calls. Honest note: this test passes on the old tree too — the abort path already failed silent, so no red was honestly achievable; the guard prevents the doomed cycle/span churn and the test locks the contract.

### R4 — same-account reopen wiped the binding (storage reviewer A)

Shape: the suspension guard preceded the idempotent same-account early return inside a catch-all that clears the binding — a redundant `openAccount(A)` while suspended threw AND destroyed the healthy bind (`notBound` on resume); a racing different-account bind did the same.
Red: `sameAccountReopenWhileSuspendedPreservesBinding` (throws `.suspended`) and `differentAccountBindWhileSuspendedFailsSafe` (`boundUserID` wiped to nil, reads `notBound`) — both **RED**.
Fix: sanitize + same-account early return first (pure memory ops, no lock), suspension refusal only for genuinely new binds, and a `.suspended` exempt rethrow that preserves the binding (invalid/different-account/migration/disk failures keep the unbound-on-failure path). New-account-while-suspended still fails safe with no file/migration touch.

### R5 — effect ordering under concurrency (concurrency reviewer, CONFIRMED blocker)

Shape: generation CAS ordered the decision but the GRDB post ran after unlock, so a stale expiry suspend could land after a foreground resume — queues re-parked while the flag reads resumed. The phase-one stress-free suite could not see it.
Red: `concurrentExpiryAndResumeAgree` hammers expiry-style suspends against resumes over a real queue and requires flag↔queue agreement per round — **RED on the old tree** (`SQLite error 4: Database is suspended` from `BEGIN DEFERRED` while the flag read resumed).
Fix: every transition holds one lock across decision + flag mutation + GRDB post (safe: GRDB's synchronous observers never reenter the policy; app-level `didResume` stays outside the lock); `reapplyIfSuspended` folded into the same discipline.
Limit (retained): the stress test exercises the race (50 racy rounds) but cannot script an exact preemption — the ordering guarantee itself is structural and code-reviewed; a green stress run alone would not prove it. The red above is genuine observed disagreement, not a proof of absence.

### R6 — BG entry fanned out foreground effects (storage + concurrency reviewers)

Shape: the BG handler called `noteResumed()`, which posts app-level `didResumeNotification` — Root's handler would then trigger sync/reap/bind from a warm-background cleanup window.
Fix: new `resumeForBackgroundTask()` — GRDB resume + flag clear + generation bump under the policy lock, NO `didResume` post; the BG handler brackets entry/exit/expiry with it. Test `BackgroundAccessWindowTests` asserts granted-window entry makes queues usable with zero `didResume` deliveries, and true foreground `noteResumed` still emits exactly one. Baseline triggers unchanged (foreground/connectivity/manual/pull-only; no new background scheduling).

### Test isolation (storage reviewer B)

Inspection: scheme `TimeOfLife.xcscheme` sets `parallelizable="NO"` on the testable reference; repo convention is injected centers/temp URLs by default with `.serialized` on 13 suites holding process-global state (Keychain/UserDefaults/network doubles).
Evidence: a temporary 3×1s probe (`ProbeSerialA/B` serialized + `ProbeParallelC` plain, since deleted) ran filtered in **3.671s total (≈1.007+1.035+1.029 serial)** — the runner executes suites serially here.
Action: added `.serialized` to the two non-`@MainActor` suspension suites (policy + store; the `@MainActor` suites already serialize on the main actor, matching convention) plus conditional-resume `defer`s everywhere (no redundant bursts). Residual, documented: `.serialized` alone would not exclude overlap with non-serialized suites if the runner ever parallelizes — but nothing else posts GRDB suspend/resume or flips the shared flag, and suspend windows are microseconds; the probe shows the current runner is serial.
`start()` no longer takes an injectable center (always `.default`, documented — GRDB observes `.default`, a custom center would silently split policy from queues).

### User-mutation catches — evaluated, NOT changed (UI/sync reviewer)

Surveyed `TrackViewModel.stop/retryStop/beginRunning/updateDraftNotes/updateDraftStartedAt`, `HistoryViewModel.performUndo`, category editor/manage view models against the baseline save-failure contract. Verdict: existing behavior is already correct — every failed user mutation preserves in-memory intent and offers retry (`stop`→`.error`+`retryStop`, notes/start→in-memory + banner converging on next load, undo→buffer intact + dialog, category editor→draft kept open). Silently swallowing a suspended Stop would be worse (lost save with no retry). No lost mutation or missing retry was proven, so no change per the reviewer's own caution.
