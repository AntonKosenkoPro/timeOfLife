# Design: drain-404-convergence

## The wedge, precisely

`drainOutbox` stops at the first throw, and pull runs after drain. Any outbox row whose push fails deterministically (record gone on relay) wedges the whole cycle: the row stays queued, pull never runs, tombstones never apply, retry repeats. The field error is entry-create → 404 `activity_not_found` (parent activity deleted + cascade-vanished relay-side).

## Decision 1: converge on push-404 (delete-wins, bounded)

In the drain's `APIError` catch, alongside the existing arms:

- entry + (create|update) + (`activity_not_found`|`not_found`) → `applyDeletionTombstone(Deletion(resource: "entry", recordID: row.recordID, deletedAt: Date()))`, remove the row, log, continue.
- activity|category + update + `not_found` → same with the row's resource (activity cascades to entries/joins inside the helper, and drops their pending rows — the exact multi-device-delete case).
- DELETE + any 404 (`not_found`, defensively `activity_not_found`) → success (extends the existing rule).
- activity|category + create + 404 → still throws (no route produces it; loud beats silent).

Why this is safe: at an entry-create 404, no pending parent create can exist (drain order is `created_at`-ordered and the FK requires the activity locally first, so any parent create already pushed successfully) — the parent is truly gone relay-side. `deletedAt: now` makes the helper's R1 keep-rule vacuous (`updatedAt > now` is impossible), so convergence is unconditional. Clean local rows are never touched by this path (only ids with queued mutations). Server-wipe mass-deletion is bounded to dirty records and requires operator-level data loss; the alternative (permanent wedge) is strictly worse.

Bonus: new-client-vs-old-relay converges lazily per record (no tombstones, but 404s self-heal), and already-wedged rows from before this fix heal on the next cycle — no manual outbox surgery.

## Decision 2: tolerate pre-tombstone relays (stateless)

`applyTombstones` catches `APIError` code `not_found` from `fetchDeletions` only → log + return without advancing the cursor. Any other error still fails the cycle. No persisted "relay lacks tombstones" flag (a later relay upgrade must just work; one cheap 404 per cycle against old relays is acceptable and documented).

## Decision 3: stop clears the timer before saving

`TimerService.stopTimer` reorders to: build entry → clear timer state → save entry. When the activity is missing (tombstoned on another device), it clears the state, skips the entry (an entry for a deleted activity is unrenderable — History JOINs activities — and unpushable), logs, and throws `TimerServiceError.activityDeleted`. Clearing first guarantees a save throw can never strand the timer in a running-but-unsavable state (the current FK-throw wedge). `TrackViewModel.stop()` maps it to `.idle` + `timer.activityDeleted` message (no ticker restart, no retry loop); all other errors keep the existing recoverable `.error` path.

## What is NOT changing

- Tombstone protocol, cycle order, delete-wins guard, R1 (all archived, untouched).
- No new outbox behavior: convergence helpers create no rows (relay already converged).
- New L10n key `timer.activityDeleted` (EN + RU + `L10n` case, per U4 + `LocalizationTests` parity).
