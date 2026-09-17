## Why

Deletions converge only on the device that made them. The relay hard-deletes with no trace, and delta pulls (`?modified_since=`) return live records only — so a second device never learns a record was deleted and keeps its copy forever. Worse, the zombie is wedged: if that device later edits it offline, the drain pushes an update for a relay-missing record, gets 404, throws, and every future cycle fails at the same row before pull ever runs.

Yesterday's `fix-delete-resurrection` (delete-wins on pull-merge) stops single-device resurrection but cannot propagate anything: it guards against live server copies, and a hard-deleted record has no server copy at all.

## What Changes

- **Relay records tombstones**: every hard DELETE of an activity, category, or entry upserts a `(user_id, resource, record_id, deleted_at)` tombstone in the same transaction; recreating an id clears its tombstone. New `GET /api/v1/deletions?deleted_since=` lists them (OpenAPI 1.4.0).
- **Client applies tombstones before draining, every cycle**: fetch deletions since the `deletions` cursor, delete the local rows (activities cascade to entries/joins locally, no outbox row — the relay already converged), drop pending create/update outbox rows for those ids (delete-wins, un-wedges the 404-update trap), then advance the cursor. Category snapshot reconciliation stays as backstop.
- **Stale-tombstone rule (R1)**: a clean local row newer than the tombstone (`updated_at > deleted_at`, both server-issued) is a recreation that won — keep it; the cursor advance buries the tombstone.

## Capabilities

### New Capabilities
- None (new endpoint, not a new capability).

### Modified Capabilities
- `sync-client`: tombstone fetch + apply + cycle reorder (tombstones before drain).
- `local-first-store`: `applyDeletionTombstone` over existing tables (no schema change).

## Impact

- Backend: migration `006_tombstones.sql`, `Store` + SQLite/Postgres impls (`ListDeletions`, tombstone writes in the three deletes, tombstone clear in the three creates), handler + route, OpenAPI 1.4.0. No GC (documented non-goal — rows are tiny, personal scale; `deleted_at` enables future GC).
- iOS: `CatalogSending.fetchDeletions`, `LocalStore.applyDeletionTombstone`, `SyncController` cycle reorder. Yesterday's delete-wins guard stays (covers buffered deletions and the pull-first window — tombstones don't exist yet in either case).
- Out of scope: running-timer dangling when its activity is tombstoned away on another device (noted in design, left as-is); tombstone GC + full-reconcile fallback; field-level LWW on delete-vs-edit (delete-wins, documented).
