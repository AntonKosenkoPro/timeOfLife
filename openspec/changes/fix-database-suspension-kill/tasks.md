## 1. Reproduction and research gates

- [x] 1.1 Record a failing regression driving the production suspension-signal path and actual bound LocalStore queue, reproducing unsafe database access/lock acquisition across suspension; distinguish it from the original device SIGKILL.
- [x] 1.2 Complete and cite Apple plus pinned-GRDB research, verify suspension/interrupt semantics, and record the HIG waiver before production edits.

## 2. Suspension-safe database access

- [x] 2.1 Implement central lifecycle coordination and direct queue preemption, preventing unsafe new work and handling queues opened while execution is unavailable.
- [x] 2.2 Preserve foreground recovery, account binding/isolation, and bounded existing background cleanup with correct expiry/completion ordering and fail-closed error handling; fix review-proven activate-cycle recovery and interrupt classification after resume.
- [x] 2.3 Add executable regressions for refusal/no-partial-state, resume/repeated transitions, new queues/account isolation, preserved snapshots and sync recovery; verify active-query interruption/rollback structurally against pinned GRDB and record its lack of deterministic public-API coverage in repro.md. Interruption remains distinct from unbound store or absent draft.

## 3. Verification and handoff

- [x] 3.1 Re-run the identical recorded regression and confirm it passes after review fixes; document commands, evidence, and physical-device limitations.
- [x] 3.2 Run iOS strict SwiftLint, warning-clean build, and full simulator test suite after review fixes; serialize xcodebuild and use an owned simulator. Full suite 1074/1074; app/test source warnings clean, pre-existing AppIntents metadata-extraction tool warnings noted in evidence.
- [x] 3.3 Run unchanged-backend gofmt, vet, lint, build and full tests on a separate parallel worker (all passed at 986db127; see evidence.md).
- [x] 3.4 Re-check relevant FURPS and delta requirements, review the final diff for lifecycle/account races, and validate the OpenSpec change. Both independent reviewers confirmed their proven findings resolved; save-failure feedback intentionally preserved; undo wording aligned to existing push-then-commit contract.
- [x] 3.5 Update architecture/runbook documentation with the implemented policy, truthful verification results, and a real-device smoke checklist; leave device-only acceptance explicitly pending if not run.
