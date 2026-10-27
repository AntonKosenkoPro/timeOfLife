## Context

See `proposal.md` — Why. Current state: `README.md` (125 lines) mixes product pitch, architecture dump (outbox/tombstones/LWW), per-config build/signing internals, release + dSYM mechanics, and 17 manual-test checkboxes. Contributor truth already lives in `docs/project-context.md` (canonical, S7), `docs/ci.md` (post-#209: GitHub PR checks + Cloud tag-archive), `docs/review-process.md` (`/review` usage), and `AGENTS.md` (agent entrypoint). No `CONTRIBUTING.md` exists, so humans have no single setup narrative and agents' behavior (worktrees, rebase-twice, `opencode.json` roles) must be reverse-engineered from `AGENTS.md`. Constraint: per-iteration rule S5 requires doc updates to stay in the same iteration as the change — this change IS the doc update, so it must also keep `openspec/config.yaml` pointers accurate.

## Goals / Non-Goals

**Goals:**
- One front door per reader: README (decide in 30s), CONTRIBUTING (contribute in 30min), AGENTS (drive agents).
- One home per fact: CI truth in `docs/ci.md`, ops truth in `docs/project-context.md`, agent rules in `AGENTS.md` — README/CONTRIBUTING link, never duplicate.
- Fix only the stale lines the move touches (counts, `docs/` listing, `add-account-deletion` wording) so the new files don't inherit rot.

**Non-Goals:**
- No `project-context.md` restructuring (its routing-changelog shrink is follow-up work).
- No CI, release, signing, or product behavior changes.
- No new visuals, binaries, or localized strings.

## Decisions

1. **CONTRIBUTING at repo root (not `docs/`, not `.github/`)**
   Rationale: GitHub discovery order is `.github/` → root → `docs/`, and root placement surfaces the Contributing tab + sidebar link (`/github/docs` — "CONTRIBUTING file best practices", fetched 2026-10-27). Alternatives considered: `docs/CONTRIBUTING.md` (consistent with other guides but lowest discovery priority — rejected); `.github/CONTRIBUTING.md` (highest priority but hides it from local browsing next to README — rejected; PR-template already lives there).
2. **Smoke checklists move to `docs/manual-testing.md`, not into CONTRIBUTING**
   Rationale: SIWA ×10 + Live Activities ×7 are runbooks with their own lifecycle (device + portal dependent); embedding them bloats CONTRIBUTING past its "30 minutes to first PR" job. CONTRIBUTING links with anchors instead. Alternative (embed inline) rejected for size.
3. **README keeps a 5-line architecture pointer, not a summary**
   Rationale: any summary duplicates `project-context.md` and rots (this change was born from exactly that rot). One line pointing at `docs/project-context.md → Incomplete / deferred` + one at `backend/api/openapi.yaml` (S10) is enough.
4. **Source-of-truth rule recorded in CONTRIBUTING**: "one fact lives in exactly one file, others link."
   Rationale: the current 3-way CI drift (`README` vs `ci.md` vs `project-context.md` post-#209) came from triplicated claims. Stating the rule makes the next author link instead of copy.
5. **Include `REFRESH_RECOVERY_KEYS` + Supabase topology in the move**
   Rationale: these are the two load-bearing omissions a fresh contributor hits (backend fail-fasts without the keyring; reboot wipes deploy-managed files). A Quickstart that omits them is broken on arrival.

## Risks / Trade-offs

- [Risk] External deep-links (landing/TestFlight URLs) rot → Mitigation: link the checked-in sources of truth (`web/`, release workflow) alongside the URLs.
- [Risk] CONTRIBUTING duplicates `project-context.md` run-steps over time → Mitigation: the source-of-truth rule + review-checklist item ("docs updated" already in PR template) catches copies at review.
- [Risk] Baseline-count fix (24/25→26) goes stale at the next spec addition → Mitigation: counts stated once in `project-context.md`; README/AGENTS/CONTRIBUTING link to it instead of repeating numbers.
- Trade-off: two new files (`CONTRIBUTING.md`, `docs/manual-testing.md`) increase the doc surface — accepted, because discovery (root placement) outweighs file count.

## Migration Plan

Docs-only, no deploy. Steps: land the file moves in one PR (≤400 lines per the review-process size discipline — split README rewrite vs CONTRIBUTING addition into stacked PRs if over); verify `openspec validate --all --strict` green (`skip_specs: true` set); verify GitHub renders the Contributing tab. Rollback: revert the commit (no state, no migration).

## Open Questions

- None blocking. The four audience/scope questions from explore (contributor depth, checklist home, source-of-truth discipline, adjacent change closeouts) are resolved above as Decisions / Non-Goals.
