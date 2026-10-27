## Why

`README.md` currently serves two audiences at once — a human deciding whether to try Lifio, and a contributor/agent needing build, signing, release, and runbook detail (125 lines incl. 17 manual-test checkboxes and release internals). The result buries the human story and duplicates contributor truth already living in `docs/` and `AGENTS.md`. Splitting into three doors — README (human presentation), CONTRIBUTING (human contribution incl. agent + environment setup), AGENTS (AI agents) — gives each reader one front door and one home per fact, which is what stops the next drift.

## What Changes

- **Rewrite `README.md` as the human front door** (~30 lines + links): what Lifio is, project status (pre-release, TestFlight), 1-minute product tour, try-it links (landing, privacy, TestFlight), contribute pointer (`CONTRIBUTING.md`), docs map. Moves build/run, signing internals, release/dSYM detail, and both smoke checklists out.
- **Add `CONTRIBUTING.md`** (new, repo root per GitHub discovery order — `.github/` → root → `docs/`): Quickstart (clone → backend runs → app runs), Environment (Go/Xcode pins, `.env` keys incl. the currently-undocumented `REFRESH_RECOVERY_KEYS`, per-config `API_BASE_URL` + signing), Agents & environment setup (what `opencode.json` roles, `AGENTS.md`, `.opencodereview/rule.json`, ctx7 login, and `/review` do; what agents will/won't do to your checkout), Checks & CI (what gates a PR, local commands, post-#209 Cloud-vs-GitHub split, `/review` usage), Manual testing (links to relocated checklists), Releases & deploys (TestFlight flow + the Supabase topology / reboot / backup warnings README omits today).
- **Relocate smoke checklists** (Sign in with Apple ×10, Live Activities ×7) from `README.md` into a new `docs/manual-testing.md`, linked from `CONTRIBUTING.md`. No checklist content changes, pure move + anchor links.
- **Consistency pass on touched references only**: baseline-count claims (24/25 vs actual 26), `docs/` directory listings (`AGENTS.md`, `project-context.md` say 3 files, actually 8), and the "active `add-account-deletion`" wording in `README.md` Deferred (shipped — `2026-10-22-add-account-deletion` is archived, `#187` merged). Updates `openspec/config.yaml` guidance only if its doc pointers go stale in the move; no routing changes.
- **Non-goals**: no product behavior changes; no API/OpenAPI changes; no CI workflow changes; no spec baseline edits; no new screenshots, binaries, or localized strings; no `history-entry-notes-icon` / `migrate-ios-ci-to-xcode-cloud` closeouts (separate changes); no full `project-context.md` de-bloating beyond the touched lines (its routing-changelog shrink is follow-up work).

## Capabilities

### New Capabilities
- None — docs-only restructuring; no product behavior changes.

### Modified Capabilities
- None — no spec-level requirement changes. This change sets `skip_specs: true` in its `.openspec.yaml` (`openspec validate` rejects a zero-delta change without that marker).

## Impact

- Affected files: `README.md` (rewrite), `CONTRIBUTING.md` (new), `docs/manual-testing.md` (new), `AGENTS.md` (doc-map line + smoke-checklist pointer only), `docs/project-context.md` (touched stale lines only), `openspec/config.yaml` (only if pointers stale).
- Systems: none (docs-only; no backend, iOS, API, CI, or signing changes).
- Authoritative docs / research bundle: `/github/docs` — "CONTRIBUTING file best practices" (root placement, discovery order `.github/` → root → `docs/`, Contribute-page surfacing; fetched 2026-10-27 via `npx ctx7@latest library` → `docs`). HIG N/A — no UI surface changed (waiver: docs-only markdown move, no app surface touched). Apple app-framework API N/A — no Apple SDK touched (waiver: diff is markdown + YAML pointers only).
