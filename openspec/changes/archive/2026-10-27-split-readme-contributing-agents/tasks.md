## 1. Research bundle (done at propose time)

- [x] 1.1 ctx7 topic query recorded: `/github/docs` — "CONTRIBUTING file best practices" (root placement, discovery order `.github/` → root → `docs/`; fetched 2026-10-27). HIG N/A — docs-only markdown move, no app surface touched. Apple app-framework API N/A — no Apple SDK touched, diff is markdown + YAML pointers only.

## 2. New files

- [x] 2.1 Add `CONTRIBUTING.md` at repo root: Quickstart, Environment (Go/Xcode pins, `.env` keys incl. `REFRESH_RECOVERY_KEYS`, per-config `API_BASE_URL` + signing), Agents & environment setup (`opencode.json` roles, `AGENTS.md` authority, `.opencodereview/rule.json`, ctx7 login, `/review` usage, worktree + rebase discipline), Checks & CI (post-#209 split, local commands), Manual testing (anchor links), Releases & deploys (Supabase topology, reboot + backup warnings), source-of-truth rule.
- [x] 2.2 Add `docs/manual-testing.md`: relocate SIWA ×10 + Live Activities ×7 checklists from `README.md` verbatim (no content changes), with anchors linked from `CONTRIBUTING.md`.

## 3. Rewrites and touch-ups

- [x] 3.1 Rewrite `README.md` as the human front door (~30 lines + links): pitch, status, 1-minute tour, try-it links (landing, privacy, TestFlight), contribute pointer, docs map. Remove build/run internals, release/dSYM detail, checklists (moved to 2.1–2.2).
- [x] 3.2 Trim `AGENTS.md`: fix `docs/` listing (3 → all 8 files) and baseline-count claim (24 → actual 26); repoint smoke-checklist pointer from `README.md` to `docs/manual-testing.md`. Keep short, no new sections.
- [x] 3.3 Fix touched stale lines in `docs/project-context.md` only: `docs/` listing, baseline-count claim (25 → 26), "active `add-account-deletion`" wording (archived, `#187` merged). No routing-section restructuring.
- [x] 3.4 Update `openspec/config.yaml` guidance only if its doc pointers go stale in the move; no routing changes.

## 4. Verification

- [x] 4.1 Run `openspec validate --all --strict` green (`skip_specs: true` set, zero deltas expected).
- [x] 4.2 Verify every moved link resolves: README → CONTRIBUTING/docs pointers, CONTRIBUTING anchors → `docs/manual-testing.md`, GitHub renders the Contributing tab.
- [x] 4.3 Re-check relevant `Requirements/FURPS/*.md` rows: confirm docs-only, no behavior rows affected; record rows checked.
- [x] 4.4 Confirm diff ≤ ~400 changed lines per `docs/review-process.md` size discipline; split into stacked PRs (README rewrite vs CONTRIBUTING addition) if over.
