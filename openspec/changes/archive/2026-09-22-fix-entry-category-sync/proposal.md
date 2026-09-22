## Why

After the `ux-revamp` merge (entries own `activity_text` + ordered `category_ids`, no activity entity), `POST /entries` rejects unknown/non-owned `category_ids` with 422 `validation_error` (`category_ids=One or more categories do not exist`). The iOS `SyncController` drains the outbox in pure global `created_at` order and aborts the whole cycle on any `default` API error, so an entry pushed before its categories — or referencing a deleted/never-synced category — wedges sync with "Sync failed. Try again." (see Profile screenshot). Pull-side already prunes unknown ids and never fails the cycle; push-side has no equivalent.

## What Changes

- Drain dependency ordering: push `category` outbox rows before `entry` rows, preserving `created_at, id` order *within* each resource (compatible with the existing "in `created_at` order within a resource" wording, now made explicit cross-resource).
- Push-side heal: on `validation_error` with `category_ids` details for an entry create/update, refetch server categories, prune unknown ids from the queued payload (remainder kept, secret-free log), rewrite the outbox payload, retry the push once, then clear the row. If nothing to prune or retry fails, fail loudly as today. The following pull converges the local copy to the pruned server version via LWW.
- **BREAKING (spec only, pre-release):** narrows `sync-client` drain ordering + adds push-prune recovery. No OpenAPI/backend/on-disk change; backend 422 contract stays.

Non-goals: no backend prune-on-create change; no rewrite of pending payloads on local category delete (covered by heal on next push); no pull-order change (already categories-first); no new UI strings.
