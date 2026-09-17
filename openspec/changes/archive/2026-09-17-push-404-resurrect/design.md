# Design: push-404-resurrect

## Why delete-wins-on-404 was wrong

The archived rule assumed every push-404 trails a deliberate delete. Tombstones-first ordering already handles exactly that case (rows dropped pre-drain), so by elimination a push-404 means the relay forgot the record with no intent on file: pre-deployment ghosts, wipes/restores, or a seconds-wide delete-vs-push race. In all of these the device holds the complete record, and deleting locally destroys user data to "converge" toward amnesia. Field case: ghost activity + fresh timed sessions — delete-wins discards every session silently with an idle status (a data black hole: the ghost survives locally, so each new session vanishes the same way). Resurrect-wins heals relay and device together; the only cost is the mid-cycle race resurrecting a concurrently-deleted record (seconds window, single user, visible and re-deletable — documented).

## Rules (drain catch, `resurrectAndRetry`, single retry, original error rethrown)

- entry create/update + (`activity_not_found`|`not_found`): re-post the fresh local entry as create (idempotent; `duplicate_import` reuses the existing resolver, which clears the row). On `activity_not_found`, first re-post the full local parent (then exactly one entry retry). Parent 409 `activity_exists` reuses `remapReferences` (moves entries, rewrites payloads in place), then retries with the rewritten payload. Parent missing locally (unreachable via FK paths; remap-leftover-safe): clear that entry's rows, keep the local entry, log.
- activity/category update + `not_found`: re-post the full local row as create (pending update rows remain and PATCH normally afterward). 409 `*_exists` reuses `resolveConflict`. Locally-missing row (name-collision remap leftover): clear its rows — this also fixes the pre-existing stacked remap wedge, where the surviving update row 404'd forever.
- activity/category create + 404, DELETE otherwise: unchanged (throw / success).
- Progress guarantee: every path either clears rows or rethrows the original error — plus idempotent replays, so no loop can spin silently.

## Pre-push stale-update guard

Update rows reference their record by id, but remaps delete losing identities and queued deletes remove rows ahead of their updates in the same drain. Before pushing any update row, the drain checks the local record still exists (`isLocallyMissing`); a missing record drops the row without pushing. This also skips pointless PATCHes for updates superseded by a queued delete (the DELETE converges the relay right after). Creates and deletes are unaffected.

## Non-goals kept

Pre-tombstone tolerance, stop-on-deleted-activity, R1, tombstones-first, tombstone protocol itself: untouched.
