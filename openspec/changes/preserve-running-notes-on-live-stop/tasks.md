## 1. Reproduce and reconfirm research before code

- [ ] 1.1 After human proposal approval, fetch/rebase onto fresh `origin/main` in this worktree; reproduce #242 with a running Track notes page containing unconfirmed text, invoke `lifio://track?stop=1`, and record the completed entry's notes/end time plus the stranded editor behavior. Keep screenshots/logs outside git; if not reproducible, stop rather than implement speculatively.
- [ ] 1.2 Reconfirm the ctx7 topic/HIG and Apple SwiftUI bundle recorded in `design.md` (iOS 18 SDK via Xcode 16+), including source IDs, exact queries, availability checks, and ActivityKit/third-party waiver reasons. Expand research before using any external API outside those waivers.
- [ ] 1.3 Add failing current-tree regressions for lost editor text and a success receipt only after a real atomic entry/outbox/draft-clear completion; reproduce nonthrowing create failure and stop retry/duplicate identity paths before fixing them. Record existing Stop timing as a preservation baseline, not a new pre-reload timestamp requirement. Tasks in sections 2–4 depend on recorded reproduction AND reconfirmed research.

## 2. Reliable immediate completion and exact entry identity

- [ ] 2.1 Preserve the existing Stop pipeline and timestamp behavior, including cold-open reload ordering and auth-gated/no-run cases; ensure later notes review/editing/resolution never changes the completed entry's end time or duration. Do not introduce earlier timestamp capture or new clock plumbing for this fix.
- [ ] 2.2 Make the LocalStore Stop transition atomically create the entry/outbox and clear the running draft, checking mutation outcomes and reusing one completion identity across retries; return an account/store/run-bound receipt with the completed-entry UUID only on success.
- [ ] 2.3 Add a notes-only LocalStore update path for that exact existing entry, preserving its latest other fields and enqueueing an ordinary update after create; handle missing/deleted rows, same-tick/LWW timestamp ordering, stale/false results, and suspension without false success or resurrection.

## 3. Track-only retained notes resolution

- [ ] 3.1 Lift only the running-notes session's baseline/current text into a retained owner; detect exact-text changes including clear/revert and snapshot before reload. Preserve History/Log Time and ordinary running-editor X/✓/back semantics.
- [ ] 3.2 Serialize Stop with editor ✓/input while completion is in flight; retain text on initial Stop failure, and bind successful completion to the exact receipt rather than the running draft or newest entry.
- [ ] 3.3 Present the post-success “Timer stopped” Review Notes / Discard Changes decision; Review shows retained editable text without validating or writing, while discard preserves confirmed notes. Keep Start unavailable until resolution/invalidation and leave the Saved confirmation/Live Activity dismissal schedule unchanged.
- [ ] 3.4 Bind the review editor's ✓ to the exact completed entry, reusing existing notes validation/counter/shake/haptic behavior; X/back discards unconfirmed edits. Preserve text independently of prompt dismissal and saved-state reset, retain failed writes for retry via ✓, and support background/foreground resumption without restarting the timer. Add no separate direct-save prompt or prompt-specific validation path.
- [ ] 3.5 Fence resolution by account/store/run identity and serialize repeated Stop/Save/discard actions; invalidate on account teardown, reject stale callbacks, and refresh ordinary entry-derived screens after a successful notes update.
- [ ] 3.6 Add all new strings to `en`, `ru`, `zh-Hans`, `es-419`, `pt-BR` plus `L10n`; use Theme colors and stable accessibility identifiers, and verify VoiceOver/Dynamic Type/Reduce Motion behavior.

## 4. Regression coverage and documentation

- [ ] 4.1 Cover delayed Review → edit → ✓, prompt discard, and review X/back discard; prove review alone writes/validates nothing, existing Stop timing is preserved, and end time/duration/other fields never change with answer or editing delay. Include clear/revert/already-confirmed notes, no-editor/cold-launch/no-run/gated/no-op/failed Stop, duplicate links, and both Island/banner routes.
- [ ] 4.2 Cover reuse of existing over-limit validation on the review editor's ✓, notes-write failure/retry without losing reviewed text, same-tick timestamps, queued-create vs already-synced-create updates, concurrent unrelated entry edits, target deletion, suspension/resume, saved reset, prompt dismissal, background/foreground, and account teardown/stale callbacks; prove no cross-entry/account writes or duplicate completion.
- [ ] 4.3 Re-check `Common.md` U1–U5/S2–S7/S10, `Timetracking.md` F1/F2/F5/F12/F15/R3/R4/S2, and `Activity_Catalog_and_Categories.md` F1/U1/U9/R1/R2/S2/S4. Update affected FURPS wording without changing API, existing per-entry isolation, or record-level LWW rules.
- [ ] 4.4 Update `Design/COMPONENTS.md` first for the retained-editor decision, then `Design/SCREENS/TimeTracking.md` and relevant `Design/INTERACTIONS.md`; update their implementation checklists, `docs/project-context.md`, and `docs/manual-testing.md`. Re-check README/OpenSpec guidance; change only if affected. Leave baselines untouched until approved archive; OpenAPI remains unchanged unless an explicitly reviewed contract change becomes necessary.

## 5. Verify and return the existing PR for review

- [ ] 5.1 On a dedicated backend verification agent, run `gofmt -l .` (empty), `go vet ./...`, `golangci-lint run`, `go build ./...`, and `go test ./...` from `backend/`, in parallel with the disjoint iOS verification agent.
- [ ] 5.2 On the iOS verification agent, run strict SwiftLint, warning-as-error build, targeted regressions then the full simulator suite using `docs/ios-test-loop.md`; serialize all Xcode builds and use one test simulator. Run XcodeGen only if project configuration changes, never edit `.pbxproj` directly.
- [ ] 5.3 Re-run the identical 1.1 repro after the fix for Review → ✓ and both discard paths, recording unchanged Stop timing/end time while delaying the answer and reviewing/editing the text; check backgrounded notes, actual Island/banner controls, truthful Saved/dismissal behavior, and no regressions in History/manual notes. Distinguish simulator evidence from any pending physical-device smoke; keep binary evidence outside git.
- [ ] 5.4 Fetch/rebase again before final PR review, re-run affected verification after rebase, and run `openspec validate --all --strict`; push implementation to this same branch/draft PR. Continue `/lifio-pr` only after implementation, with normal CI and AI/human review; never merge or archive without the required human action/approval.
