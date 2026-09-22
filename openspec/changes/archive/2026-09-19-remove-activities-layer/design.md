## Context

See `proposal.md` for motivation. Current state: entries hold `activity_id NOT NULL → activities ON DELETE CASCADE`; categories attach via `activity_categories(position)`; entries resolve name + categories at query time (F9/D24 rule). `timer_state(activity_id, activity_name snapshot, started_at)` backs the running timer; `SyncController` syncs three resources with LWW, `activity_exists` remap, parent-heal, and cascade tombstones. Constraints (see `docs/project-context.md`): `LocalStore` is the single mutation chokepoint; `openapi.yaml` is the authoritative contract (S10); no backward compat for on-disk formats (pre-release); EN+RU strings + `L10n`; XcodeGen-managed; `Theme` colors only.

## Goals / Non-Goals

**Goals:**
- Entries own `activity_text`, ordered `category_ids`, and `notes`; history never mutates retroactively.
- Capture stays frictionless: plain text + 6 exact recents + live tags while running.
- One migration, one contract cutover, no dual-write period.

**Non-Goals:**
- Search-as-you-type, bulk rename-all-text, Discard-running, entry-detail surface, ControlWidget target (no `project.yml` target exists).

## Decisions

**D1 — Trimmed exact identity (case-sensitive).** `trim(text)` byte-exact; `Gym` ≠ `GYM`. Considered: normalized lower() grouping (fewer forks) — rejected: user explicitly wants case-distinct activities. Trim stays to avoid `"Gym "` ghosts; validation (non-empty trim, 60 chars) unchanged.

**D2 — `entry_categories(entry_id, category_id, position)` join, not an array column.** Mirrors the old `activity_categories` shape, keeps ordered selection (`TagSelector` parent owns order), queryable per-category, cascade on entry/category delete. Considered: JSON array on entries — rejected: ordering + join-cascade + existing `SyncController` join handling favor the join.

**D3 — Draft-until-Stop in transposed `timer_state`, not entry-at-Start.** `timer_state(activity_text, category_ids snapshot, started_at, status)`; entry + single outbox row created once at Stop. Considered: entry-at-Start (explored, reverted) — rejected: sync churn on every toggle, Cancel/discard semantics, History/Insights exclusion bookkeeping. Draft preserves today's "one outbox row per entry" economics and needs no Cancel path.

**D4 — Name locked, tags live while running.** `TagSelector` select-only from existing categories (no creation mid-run), zero allowed. Toggles rewrite the draft snapshot only. Considered: editable name mid-run — rejected: forks recents identity mid-session. Considered: notes on the running view — rejected: notes stay entry-sheet-only, new entries start `""`.

**D5 — Recents as a query, not a table.** `GROUP BY activity_text_exact`, per group keep the row with `max(started_at)`, order groups by that max DESC, `LIMIT 6`; chip icon = that row's first-position category. Index `(user_id, activity_text, started_at DESC)` keeps it cheap. Considered: maintaining a recents table — rejected: derived data, write amplification, second source of truth.

**D6 — History tap opens the entry form directly.** Delete `ActivityDetailView`/VM/route; `HistoryView` presents the unified form as a full-screen cover (EDIT/LOCKED). Considered: replacement activity-grouped view — rejected: no identity left to group by; Insights exact-text lens covers aggregation.

**D7 — Entries-only sync.** Payload `activity_text + ordered category_ids + notes`; unknown category ids pruned with remainder kept (logged); no remap, no parent-heal, no activity tombstones; category-record `category_exists` remap stays. In-progress drafts never enter the outbox. Considered: syncing drafts live — rejected: churn + LWW races with self.

**D8 — One-shot migration, no compat.** Backend migration + `LocalStore` v2: add columns/join, backfill each entry from its activity's current name/ordered cats/notes, drop `activities`/`activity_categories`, remove `/activities*` routes. Pre-release rule permits breaking; relay and app cut over together. Undo-buffer activity snapshots dropped (entry/category snapshots stay).

## Risks / Trade-offs

- [Risk] Recents `GROUP BY` slows at 10k+ entries → Mitigation: covering index above; cap 6 bounds sort output.
- [Risk] Typo forks (`Gy m` vs `Gym`) split recents/lens rows → Mitigation: accepted per spec (No#2); exact chips make forks visible and one-tap fixable on the next entry.
- [Risk] Rename-all becomes N entry writes → Mitigation: accepted (rare by design); no bulk endpoint in scope.
- [Risk] Category deleted mid-run prunes silently at Stop → Mitigation: toggle UI hides it immediately; Stop logs the prune; remainder saves.
- [Risk] Relay/app version skew during cutover → Mitigation: pre-release, no compat window; `openapi.yaml` + contract tests gate both sides in the same change.
- [Risk] `TrackState`/`TimerService` rewrite ripples into compact timer + widgets → Mitigation: draft read path mirrors today's `timer_state` read; compact timer shows text only.
