# Execution notes — task 1.3 chronology (2026-10-30)

Scope: this file records the EXACT chronology of the task 1.3 seam-test
evidence for `app-store-screenshot-pilot`, plus the human disposition on the
process deviation. It does not change any baseline spec or production
behavior, and it approves no asset.

## Original requirement (quoted, preserved — not rewritten)

Task 1.3: "Before changing any existing injected-clock bypass, record failing
tests on the current tree for History `load()` and relevant Track/compact-timer
paths; keep the same reproductions for after verification."

## What actually happened (executed record)

1. **Four seam tests did NOT follow test-first order.** The History-`load()`,
   Track-`start()` anchor, Track-`stop()` endedAt/duration, and adopted-draft
   elapsed tests in `TimeOfLifeTests/CaptureClockSeamTests.swift` were written
   alongside/after the clock-forwarding fixes. Their "fail on the pre-fix
   tree" status was initially bypass-line analysis, NOT executed proof. (The
   compact-stop test binds the new `AppShellViewModel(now:)` seam and has no
   baseline counterpart — labeled as such from the start.)
2. **Retrospective baseline red (executed later, honestly labeled).** The four
   assertions were run as `BaselineClockSeamTests.swift` in a detached scratch
   worktree on the pristine `c3e5911` tree (pre-existing seams only; bypass
   line verified present at `HistoryViewModel.swift:58`): executed
   BASELINE-RED, EXIT=65, 4/4 failed with 7 issues (History load dayGroups +
   label; Track start anchor; Track stop duration + endedAt +
   durationSeconds; adopted elapsed). Log: `screenshot-pilot-baseline-repro.log`.
   The identical assertions pass on the fixed tree (filtered + full Debug
   suite). Scratch worktree removed after the run.
3. **One seam DID a true red-before-fix cycle.** The DST calendar test
   (`Started-at edit resolves in the model calendar`) executed RED with the
   fix withheld (EXIT=65, 1 of 6 failed — exactly the predicted 1-hour DST
   gap; log `screenshot-pilot-red-proof3.log`), then GREEN 6/6 after the
   one-line fix (`updateDraftStartedAt` passes `calendar:`; production default
   `.current` unchanged; log `screenshot-pilot-green-proof.log`).

## Human disposition (2026-10-30)

After a plain explanation — 4 clock fixes were written before their failing
tests; pristine original code later failed all 4; fixed code passed — the
human said **'Ok, record this.'** The deviation is therefore recorded (here
and in task 1.3's note) and the pilot continues on the strength of the
retrospective evidence.

## What this disposition is NOT

- NOT a claim that chronological test-first order was originally followed.
- NOT a blanket waiver: the per-iteration reproduce-before-fixing rule
  (`docs/project-context.md` → bugfix rule) stands UNCHANGED for every future
  bugfix. This disposition covers this instance only.
- NOT asset approval: task 5.4 remains unchecked; no screenshot is claimed.

## Sources

- `openspec/changes/app-store-screenshot-pilot/evidence-ios.md`: §"Failing
  clock tests first" (original analysis wording), §Verification accuracy
  correction (analysis ≠ proof), §"Red-proof runs" (DST executed cycle),
  §"Failing-before status, honestly graded" + isolated-baseline run.
- Core logs (named in evidence-ios.md, kept outside git):
  `screenshot-pilot-red-proof3.log`, `screenshot-pilot-green-proof.log`,
  `screenshot-pilot-baseline-repro.log`.
