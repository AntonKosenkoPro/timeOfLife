## Why

Field evidence against live tombstone infrastructure overturned the previous change's core rule. Device B pushes entries for an activity missing relay-side with no tombstone on file (pre-deployment ghost: deleted before tombstones existed, so no tombstone will ever arrive). The archived `drain-404-convergence` rule would converge by *deleting* — silently discarding fresh user sessions into the ghost's black hole, and every future session timed against the surviving ghost would vanish the same way with a clean idle status. Worse, the same rule applied to a stale activity-update row left behind by a name-collision remap would delete the freshly adopted server winner.

Tombstoned deletes are unaffected (tombstones-first drops those rows pre-drain, so a tombstoned record never reaches push-404). A push-404 therefore always means "relay forgot, no delete intent on file" — and the device holds the fuller record. The correct policy is resurrect-from-local with exactly one retry, else surface loudly. Nothing is ever silently dropped.

## What Changes

- **Resurrect-and-retry (replaces delete-wins convergence)**: entry create/update → `activity_not_found`/`not_found` and activity/category update → `not_found` re-post the full local row (entry as create; activity/category as create; entry-update as create first) and retry the push once. A missing parent is re-posted before the entry retry (409 `activity_exists` on the heal reuses the existing remap flow, which rewrites the entry payload in place). Any further failure rethrows the original error loudly. Locally-missing rows (remap leftovers) just clear their rows.
- Unchanged: DELETE-404 success, activity/category CREATE-404 throws, pre-tombstone `fetchDeletions` tolerance, stop-on-deleted-activity, R1, tombstones-first ordering.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `sync-client`: push-404 rule changes from delete-wins convergence to resurrect-and-retry (REMOVED + ADDED: the archived requirement's scenarios no longer apply).

## Impact

- iOS only (`SyncController` drain path + tests). No schema, OpenAPI, or backend change. Supersedes the archived `drain-404-convergence` push-404 requirement; every other requirement of that change stands.
