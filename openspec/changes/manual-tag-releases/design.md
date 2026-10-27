## Context

See proposal.md (Why) for motivation. Current state: `release.yml` bumps `project.yml` + mirrors Release plists + pushes commit and `vX.Y.Z` tag atomically to `main` — the push leg is dead under the `main protection` ruleset (dry run `40211312698`, `GH013`). Tags are unprotected (only one branch ruleset exists; the tag leg died solely via the atomic transaction). Xcode Cloud has two workflows in App Store Connect (invisible from the repo): `iOS PR Checks` and the tag workflow (`Tag Changes v*` → Test → Archive); the only in-repo Cloud surface is `ci_scripts/ci_post_clone.sh` (xcodegen-only). Backend has no identity: always-overwritten `:latest` image, `/health` → `{"status":"ok"}`, one `stage` environment while `backend.yml:92` defaults to it against a comment promising `prod`. Constraints: S6 mandatory-check coverage must survive; Debug unsigned / Release signed `7923U48U87`; XcodeGen-managed; `openapi.yaml` is authoritative for the `/health` shape change (S10).

## Goals / Non-Goals

**Goals:**
- Make the owner's signed tag push the single release act for both channels and the backend, with zero bot writes to `main`.
- Preserve the exact `ios.yml`-era enforcement bar under Cloud ownership (lint + warnings-as-errors + tests) plus a build-time unanimity assertion replacing the deleted release guards.
- Give every shipped artifact a two-string identity (iOS Profile row, backend `/health`).

**Non-Goals:**
- No Archive-destination automation choices beyond wiring the two tag patterns (owner configures Internal vs External/Store in ASC).
- No Cloud→GitHub status back-reporting; no OTel/SLO telemetry; no iOS↔backend version coupling.

## Decisions

- **D1 — Namespace grammar `internal/vM.m.p[.n]` / `release/vM.m.p[.n]` / `backend/vM.m.p`.** Prefix routing is glob-friendly for Cloud tag patterns and fail-closed on typos. The optional fourth-dot re-upload sequence keeps marketing pure semver while giving every upload a distinct tag name (tags never move). Alternative (suffix `-internal.1`, semver-prerelease style) rejected: confuses `git describe` and semver parsers; alternative (decoupled counters like `internal-42`) rejected: loses the marketing linkage testers read.
- **D2 — Cloud per-workflow run number as the ASC build counter.** App Store Connect needs increasing integers per marketing line; the committed `CFBundleVersion` counter dies with the bump commit. Each Cloud workflow's run number is monotonic within that workflow, and internal/public are separate workflows on separate marketing lines, so they never collide. Alternative (commit count) rejected: rebases rewrite it. Fallback if run numbers prove resettable: fourth-dot sequence × constant stride + run number, decided at apply time from ASC docs, no spec change needed (specs only require "increasing").
- **D3 — Stamp at build time in extended `ci_post_clone.sh`; assert unanimity there.** Parse tag → `MARKETING_VERSION`/build/`CHANNEL`, stamp every target (app + appex + framework `MARKETING_VERSION` for ITMS-90057) after `xcodegen generate` (generation rewrites plists, so stamping must follow it — the `add-version-label-release` spike proved generation wins). A unanimity assertion across targets fails the archive on skew, replacing the deleted `release.yml` guards at the point where skew actually ships. Alternative (stamp in `ci_pre_xcodebuild.sh`) rejected: keep one script phase owning versions; post-clone already runs `generate`.
- **D4 — You-only signed tag rulesets; branch ruleset untouched.** New rulesets on the three namespaces with the owner as sole bypass actor + required signed tags. Even a compromised `GITHUB_TOKEN` cannot release. Alternative (bypass-allowlist the bot, keep bump pushes) rejected: reopens the exact hole branch protection just closed and preserves the build-N race.
- **D5 — Revert-forward rollback; expand-contract migrations.** iOS rollback is a revert commit + new tag through internal first (Apple forbids downgrades; ASC retains every build). Backend rollback redeploys the previous pinned image; from this change on, migrations MUST be expand-contract (new code reads old+new schema; destructive drops ride a later release) so schema never blocks a redeploy. Alternative (tag moves/deletes) rejected: destroys the audit trail the whole system is built on.
- **D6 — Backend identity via `ldflags` + pinned image tags.** `--build-arg TAG/SHA` → `-X main.version/main.sha` → `/health` `{version, sha}` with `"?"` fallback unstamped. Response stays backward-compatible (`status` field untouched). Image push adds `backend:<tag>` alongside floating `:latest`. Alternative (version file in repo) rejected: reintroduces a committed counter with its own race.
- **D7 — GH environments deferred to Phase 3.** `testflight-internal`/`testflight-public`/`backend-prod` with a wait timer (for solo, the timer catches "oops" dispatches; self-review theater is skipped). Tracking-only at first; Cloud status reconciled manually until a webhook exists.

## Risks / Trade-offs

- [Risk] Cloud run numbers reset per workflow recreation → duplicate ASC build numbers → Mitigation: verify monotonicity claim against ASC behavior during Phase 1 proof builds; D2 fallback (sequence × stride) ready, no spec change needed.
- [Risk] Tag typo "does nothing" reads as broken tooling → Mitigation: runbook one-liner in `docs/ci.md` (check tag spelling → check Cloud build list); fail-closed is the intent, documented as such.
- [Risk] Signing-key loss blocks all releases by design → Mitigation: key in two places from day one; revocation/rotation procedure recorded in `docs/ci.md`.
- [Risk] Internal builds hit prod backend until the stage override lands → Trade-off accepted (account isolation partitions dogfood data); the override is Phase 3, explicitly not a Phase 1 gate.
- [Risk] Cloud build logs invisible in PRs; stamped-version skew surfaces only in ASC → Mitigation: unanimity assertion fails loudly with the mismatched values in the log excerpt pasted as task evidence.

## Migration Plan

- **Phase 0 — unblock (settings + one paragraph).** Create the three tag rulesets (manual operator step, verified via `gh api` output); document "bump retired, tags are the release act" in `docs/ci.md`. Next release can already go out as a manual tag (project.yml values + tag message carry it) before any stamping exists.
- **Phase 1 — iOS channels.** Extend `ci_post_clone.sh`, create Cloud workflows A/B on the two tag patterns, Profile channel badge, delete `release.yml` bump machinery, rewrite `release-versioning` deltas into the baseline on archive.
- **Phase 2 — backend identity.** Tag trigger + pinned pushes in `backend.yml`, `ldflags` stamping, `/health` fields + `openapi.yaml` sync, fix `stage`/`prod` split.
- **Phase 3 — timeline + drill.** Create the three environments, record the rollback drill per platform (internal-only), fold learnings into the runbook.
- **Merge order:** coordinate with `migrate-ios-ci-to-xcode-cloud` (owns the GH→Cloud cutover + the same five docs) — either land the cutover first and rebase this change onto it, or fold that change's remaining tasks into Phase 1 here. The doc edits land once, not twice.

## Open Questions

- Workflow B's Archive destination: TestFlight External only, or straight to App Store submission? (ASC-side config, no spec/task impact — owner decides at Phase 1 wiring time.)
- Bad-tag policy: leave mistyped tags in place with a record, or delete + note? (Docs one-liner; leaning keep — deletion weakens the never-move norm by example.)
- Internal→stage backend override timing: Phase 3 as planned, or earlier if dogfood touches shared prod data uncomfortably? (Does not gate Phases 0–2.)
