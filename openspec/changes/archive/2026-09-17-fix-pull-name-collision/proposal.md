## Why

First sync against a relay that already holds data (the production account) fails permanently: the pull-merge upserts each server category/activity by id, but a same-named local row with a different id (fresh-device seeds) violates the case-insensitive unique-name index, aborting the whole cycle before the outbox ever drains — and every retry fails identically.

## What Changes

- Pull-merge resolves same-name/different-id collisions by record-level LWW on `updated_at`: the newer side owns the name; adopting the server identity reuses the atomic remap machinery (no new server dependence, offline-safe).
- Server activities are translated to local category ids (by id, else by normalized name from the pulled snapshot) before merging, so joins never reference a skipped server category.
- Entries whose activity is absent locally (skipped server branch) are skipped with a log instead of failing the cycle on the FK constraint.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `sync-client`: pull-merge collision recovery (newer-owns-the-name), category-id translation on activity merge, dangling-entry skip.

## Impact

- `SyncController.pull`/`applyServer` paths only; `LocalStore` needs no schema changes (existing `activity(named:)`/`category(named:)` lookups + remap functions reused).
- No OpenAPI changes; no backend changes (the relay contract is unchanged).
