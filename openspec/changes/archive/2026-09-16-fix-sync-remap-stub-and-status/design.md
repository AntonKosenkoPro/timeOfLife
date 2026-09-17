# Design: Sync Remap, Status & Failure Transparency

## Context

See `proposal.md` (Why) for motivation. Grounded facts (read-only forensics, no behavior changed yet):

- `SyncController.remapReferences` (`Features/Sync/SyncController.swift:319-358`) merges `Activity(id: newID, name: oldID)` / `Category(id: newID, name: oldID)` stubs when the winner fetch fails; `store.mergeActivity/mergeCategory` upsert them with `updated_at = Date()`, after which LWW (`server.updated_at > local.updated_at` in `applyServer`) can never replace them. Backend winner `{id, name}` details verified correct; starter seeding uses localized names; wire DTOs map cleanly — the stub is the sole corruption source.
- `ProfileView`: `syncStatusRow` renders "Syncing…" while `syncNowTitle` retitles the disabled button to the same string (two rows). The `.error` case drops the associated message `SyncStatus.error(String)` already carries.
- `APIError.errorDescription` emits codes + server messages + string details only — safe to display (no tokens/bodies/emails by construction).

## Goals / Non-Goals

Goals: stop the corruption at the source, make status singular, make failures self-describing — all with unit coverage on the decision points.

Design-level non-goals: no protocol/retry-policy changes, no in-app log viewer, no server changes, no migration.

## Decisions

### D1: Fetch-or-rethrow in remap recovery (no stubs, ever)
Both `*_exists` branches fetch the winner first; any fetch failure rethrows out of `resolveConflict` → `drainOutbox` → `runCycle`, which sets `.error`. The rethrow propagates before the shared `removeOutboxRow`, so the row stays queued and the next trigger retries the identical row — idempotent by construction.

The activity branch additionally adopts the winner through a new atomic `LocalStore.remapActivityReferences` (tombstone the loser to free its normalized name → merge the winner → move entries → delete the loser, one transaction): the `lower(name)` unique index would otherwise turn the winner merge into a constraint failure while the loser still exists. The category branch already had its atomic equivalent. The tombstone never escapes the transaction, so a crash can never leave a UUID-named row behind; moved entry ids return to the caller for outbox-payload rewrite. The now-unused `updateEntryLocal` helper is removed.

*Alternatives considered*: stub with a placeholder name + `distantPast` timestamp so LWW heals later (rejected — a second failure mode that still writes fake content into user-visible lists; retry is strictly safer and the row is already idempotent); falling back to the losing record's own name under the winner id (rejected — same fake-content class, wrong attribution).

### D2: Button keeps its title; status row owns "Syncing…"
`syncNowTitle` returns "Sync now" unconditionally; `.disabled(status == .syncing)` stays. One-line view change, verified on-device (the duplicate only manifests mid-cycle).

*Alternative considered*: hiding the status row while syncing and letting the button carry it (rejected — inverts the established surface ownership: the row is the status surface in all other states).

### D3: Error message to the surface and to the log
Profile's `.error` row keeps its title and gains the message as a subtitle (fallback to the generic string when empty). `SyncController.runCycle` logs cycle start/finish plus failure code via `Logger` (subsystem = bundle id, category `sync`); messages logged are the same secret-free strings surfaced in UI. Poisoned locals are repaired by in-app rename (bumps `updated_at` → LWW push heals both sides); deletion is explicitly NOT the repair (it would push a real delete of the winner).

## Risks / Trade-offs

- [Risk] Rethrow on winner-fetch failure turns a recovered collision into a cycle error → Mitigation: correct trade — a visible, retryable error beats silent corruption; the row retries on the next trigger automatically.
- [Risk] Rename-heal depends on the winner id surviving locally (it does — stubs carry the winner's id) → Mitigation: verified as a task on a temp store mirroring the poisoned shape.
- [Risk] Error subtitles expose server strings users can't act on → Mitigation: generic title stays primary; the message is a secondary line for diagnosability, exactly what the reporter asked for.

## Migration Plan

None. No schema, contract, or flag changes. Rollback = revert of the three code sites.

## Open Questions

None — failure paths enumerated above; the exact production failure that poisoned the reporter's device is unknowable without device logs, which the logging in D3 addresses structurally.
