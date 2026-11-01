## Context

See `proposal.md` for motivation and scope. Planning is based on `main` at `a038829f` (2026-11-01), not on the unchecked tasks of old changes.

- The only current entry writers use `source="manual"`: `TimerService`, Log Time, and the fallback `StopTimerIntent`. No provider connector exists.
- Both visible Live Activity Stop controls normally use `LiveActivityDeepLink.stopURL`. `TimeOfLifeApp` requests an Island stop; `AppShellView` selects Track, awaits `reloadTrack()`, and calls `trackVM.stop()`. The intent is used only by nil-URL fallback views.
- `LiveActivitySignal.post()` has one producer: the fallback intent. Its Darwin observer, `handleExternalStop`, and `.timerStoppedExternally` form an otherwise unreachable refresh chain.
- `ActiveAccountFileResolver.resolve()` also has only the intent as a production caller, but its session-marker helpers are used by `SessionCache` and `AccountDeletionCoordinator.clearOwnedSessionState`. The whole file is not dead.
- The backend is deployed. Its migrations must remain rollback-compatible (`docs/project-context.md`, “Schema discipline”). Local on-disk shapes follow the separate pre-release no-compatibility policy; neither rule overrides the other.

## Goals / Non-Goals

**Goals:**
- One source-free entry model and one editable saved-entry path.
- One Live Activity Stop mechanism: open the app, load the bound account, stop through the normal mutation path.
- Remove directly orphaned code/build dependencies, not merely hide the integration labels.
- Preserve account isolation, local-first mutation/outbox semantics, and deployed backend rollback.

**Non-Goals:**
- Removing Live Activities, changing their appearance, running-timer editing rules, navigation, timer precision, or Saved-card timing.
- Rewriting sync/reaping, auth, account deletion, or tests unrelated to this retirement.
- Removing unrelated unused auth methods/clock dependencies, changing Kafka plans, archiving other changes, resetting user data, or dropping deployed backend columns in this release.

## Decisions

### D1. Remove provenance rather than reduce it to a one-value enum

Remove `source`/`sourceRef` from `TimeEntry`, create payloads, wire shapes, local SQL, outbox payload encoding, undo snapshots, fixture builders, and presentation. Entries keep IDs, text, ordered categories, notes, timestamps, and duration. `EntryFormMode` has only CREATE and EDIT; any saved entry opens EDIT, including entries whose old relay rows contain non-manual provenance. Do not replace seven source-specific labels with a generic “imported” label or lock.

Remove `EntryProvenance`, History row provenance inputs/accessibility fragments, imported-title/note strings, and the corresponding `L10n`/localization-test entries in all five locales. Shared Stop/Saved-card strings remain live and must not be removed with the provenance block.

Alternative rejected: retaining `source="manual"` indefinitely preserves branches and testing overhead without useful information. Existing entry-ID idempotency is not import deduplication and remains required.

### D2. Source-free public API now; physical backend contraction later

This release removes provenance from Go entry/request types, scanning/query projections, response JSON, documented request/response schemas, validation, and import-conflict mapping. Omit the retired columns from entry INSERTs so their existing defaults (`source='manual'`, `source_ref=NULL`) apply. Do not rewrite existing rows, backfill their provenance, drop the partial index, or edit migration `004_provenance.sql`. Existing rows and categories, IDs, content, timestamps, and joins remain intact. No provenance column is needed by the new code.

Older request bodies carrying `source`/`source_ref` are accepted and those keys ignored by the existing permissive JSON decoder. They never select editability or an import-deduplication path. Current responses omit both keys, including get/list/create/update/conflict responses. `duplicate_import` is no longer a generatable entry error. Same-ID replay still returns the existing entry; different IDs are independent even if obsolete external references match.

The retained physical columns/index are explicitly transitional deployment residue, not a supported product feature. No destructive migration is authored in this change. A later contract release may drop them only after all deployed readers/rollback candidates stop referencing them, with fresh/upgrade and rollback evidence. Keeping retired wire fields as deprecated echoes was considered and rejected: `EntryWireDTO` already uses `decodeIfPresent` with a manual default and optional source ref, so the current app tolerates source-free responses. Verify this in a rollout matrix rather than keeping unused API surface by assumption.

### D3. Existing mixed-version compatibility is sufficient; no local legacy branches

| Client / relay | Expected behavior |
| --- | --- |
| Current app / new relay | Missing response provenance defaults safely in the current wire decoder; outgoing obsolete keys are ignored by the new relay. |
| New app / current relay | New app ignores extra response provenance; omitted request provenance uses the current relay's manual/null defaults. |
| New app / new relay | No provenance in either direction; every saved entry is editable. |

The concrete current decoder is `RemoteCatalogRepository.swift:361–379`; backend `decodeJSON` does not disallow unknown keys. Pin the matrix with tests. An older unsupported build with different decoding behavior is not silently declared compatible: inspect the deployed client baseline before rollout.

Local GRDB schema/Codable shapes are edited in place under the current pre-release policy; do not add `legacySource`, format-detection, dual-shape migration, or anonymous-to-account migration. Test with fresh isolated stores. This is not authorization to erase any account's local files or queued data. At apply, reconfirm that this policy still applies to the installed builds in scope; if real supported local data requires an upgrade path, stop and revise the plan with the owner rather than silently wiping it.

### D4. Link-only Live Activity Stop; remove the independent writer and its bridge

Keep the existing path:

```text
Island / Lock Screen Stop link
  → lifio://track?stop=1
  → app auth/account gate and Track navigation
  → await reloadTrack()
  → TrackViewModel.stop()
  → TimerService / LocalStore + outbox
  → normal Live Activity Saved card and timed end
```

Delete `StopTimerIntent`, `LiveActivityStopButton`, and `LiveActivityStopPill`. Keep the two Link views, their circle/pill labels, theme, accessibility behavior, and luminance treatment. Make the fixed Track/Stop URL contract non-optional with a checked static construction: invalid hard-coded URLs are programmer errors caught by tests and a clear construction assertion, not a runtime reason to select a second persistence path. Keep incoming URL parsing defensive; malformed external links must not start/save a timer. Do not replace Stop with a misleading return-only link, hide the normal Stop control, or introduce an AppIntent replacement.

Delete `LiveActivitySignal` and its app-side Darwin registration/teardown, handler box, `handleExternalStop`, `.timerStoppedExternally`, and the two observers. Keep the navigation stop-request replay filter (`> 0`), gate/shell readiness, reload-before-stop ordering, sign-out request reset, and all normal stop/save/error handling. A URL received while signed out never creates anonymous data or writes a dormant account's draft.

Alternative rejected: moving duplicate stop code into another extension helper still leaves a second writer. An intent is not required for the currently shipped open-and-stop interaction.

### D5. Prune dependencies by actual callers, not by names

After deleting the intent, remove `ActiveAccountFileResolver.resolve`, that resolver's `Resolution` enum (not the unrelated account-deletion coordinator enum), and tests whose sole contract is the retired extension resolver. Retain/extract the session-marker URL/name/read helpers still used for cached-session mirroring and account-deletion ownership checks, including the injected `sessionDefaults` initializer used by marker reads; do not reserve unused APIs for the abandoned Control plan. In mixed sidecar tests, preserve marker-mirroring assertions and retarget only the removed resolver assertions. Preserve fail-closed marker clearing and the “delete A while B is active” guard, with focused tests for the retained helper.

Recalculate `LifioLiveActivities` source membership after the last extension database consumer is gone. Remove its explicit compilation of `LocalStore`, resolver, ID/outbox utilities, and catalog models that have no rendering caller; remove the extension's GRDB dependency if no remaining source needs it. Keep those files/dependencies in the main app wherever still live. Retain `LifioLiveActivityCore`, widget rendering, localized resources, version-stamping/signing configuration, and App Group identity/location. Regenerate the project only via XcodeGen; never hand-edit `.pbxproj`.

Keep `endOrphanedActivities`, the foreground sweep, draft-gone reconciliation, background reap registration/scheduling, and the entry-recency duration heuristic. They handle crashes between save and end and stale system activities independently of the deleted signal. Update misleading intent-specific comments without redesigning these mechanisms.

### D6. Retire product contracts without losing shared guarantees

Remove all requirements from `entry-provenance` and `lock-screen-controls` through change-scoped deltas. Re-home the iOS 18 floor in `app-shell` first; no iOS 18 availability branches or deployment downgrade are introduced. Keep App Group location, `.completeUntilFirstUserAuthentication`, per-account storage, same-account sync, and LocalStore's single-mutation-chokepoint rule.

Where a requirement contains scenarios that are intentionally retired (LOCKED mode, a Control/extension writer, or source-defaulting), use explicit REMOVED plus replacement ADDED requirements with Reason/Migration and meaningful new names. Do not silently omit baseline scenarios from MODIFIED blocks or preserve misleading scenario names solely to satisfy the scenario-loss guard. Unchanged behavior/scenarios remain in the replacement in full.

The change metadata explicitly sets `retire_capabilities: true`: after all requirements of `entry-provenance` and `lock-screen-controls` are removed, the approved archive can retire those baseline files instead of leaving invalid empty capabilities. During approved spec sync/archive, also reconcile stale Purpose prose for the surviving entry-editor/local-first-store/Live Activities capabilities (editable entries, app-owned persistence, Stop opens the app). No baseline is edited during proposal creation.

Rewrite extension-mutator scenarios as app stop/account-cleanup overlap scenarios where their safety guarantee remains useful. Do not invent a Live Activity database reader to replace the retired Control: faces render app-published ActivityKit content, not a new polling/database path.

Update current Requirements, Design and context documents together with implementation. Archives remain historical evidence, not text to mass-replace. The retirement includes removing “deferred Control” instructions that would otherwise ask later agents to rebuild it. Other active changes are not archived or rewritten here.

### D7. Research and policy basis

Context7 was queried on 2026-11-01:

- Resolved **ActivityKit** to `/websites/developer_apple_activitykit` (official Apple source).
- Query: “iOS 18 SDK via Xcode 16+: open the containing app from a Live Activity Stop Link or widgetURL, handle the URL in the app, and end the Live Activity from app code”. Sources: `https://developer.apple.com/documentation/activitykit/launching-your-app-from-a-live-activity` (deep links), `https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities`, and `Activity.end(_:dismissalPolicy:)` (final content and app-side ending).
- SDK scope is iOS 18 via Xcode 16+, retaining the existing iOS 26 presentation branch. No new API is selected from an unpinned newer SDK.
- Topic and Apple API research share that query because the topic is the retained Live Activity navigation path.
- HIG-specific lookup waived: this change introduces no new face/layout/control or editor grammar; it retains `Design/COMPONENTS.md`, `Design/SCREENS/EntryForm.md`, and the existing Live Activity navigation design while removing unused/read-only branches. The direct HIG page was attempted but returned no usable content; it is not cited as evidence.
- External-library/best-practice lookup waived: no new dependency or storage mechanism; backend migration and local-format decisions are fixed by `docs/project-context.md` rather than a new database recipe.

Reconfirm source documentation and policy applicability at apply time; request a new lookup if the retained mechanism changes. This is planned feature retirement, not a bugfix; record the current writer/caller graph and regression baseline before implementation, without claiming an unperformed runtime reproduction.

## Risks / Trade-offs

- [Accidental loss of a still-live account-cleanup helper] → Keep marker-reading/mirroring calls and cover deletion of A while B is active; remove only the retired resolver operation.
- [Broad search-and-delete removes rendering labels/resources or crash reaping] → Separate writer-only symbols from shared Stop visuals, Saved strings, and lifecycle safety nets; test cold-open, ordinary stop, and orphan reap independently.
- [Backend rollback breaks after a column drop] → No destructive migration or provenance backfill in this release; retained defaults/index let the old image run.
- [Retired provenance remains on deployed rows] → It is deliberately ignored, never exposed or used to lock an entry, and preserved physically until the later schema-contract release.
- [Existing installed local databases need support despite the pre-release note] → Apply-time release-policy gate; never silently delete user account files, outboxes, or undo buffers to make tests pass.
- [Cold-open Stop is lost or repeated] → Preserve request replay, reload/stop sequencing and no-draft no-op; prove both banner and Island paths, including a terminated app.
- [A stale face survives account changes] → Preserve existing account scoping/reset/teardown; test signed-out no-write and cleanup isolation. This change does not add an account identifier to the public stop URL.

## Migration Plan

1. Rebase on fresh `origin/main`; reconfirm policies/research and record current contracts/callers. No production read/write is needed for proposal creation.
2. Implement the source-free client and relay plus tests together. Do not edit historical migrations or issue live database DDL. Local fixture stores use the new pre-release shape.
3. Verify the three client/relay combinations above and compare entry counts/IDs/content/categories/timestamps before and after a representative upgrade/read/update; inspect deployed client versions before release. Any operator query is read-only and records aggregate provenance presence, never entry text or external IDs in logs.
4. Deploy the relay through the normal pipeline; either app/relay order is supported by the tested current-version matrix. Release the app through the existing owner-tag workflow, not as part of this planning task.
5. Roll back the backend by redeploying the previous pinned image: unchanged columns/defaults/index remain available. Do not add an automatic iOS on-disk downgrade mechanism; local-format support is subject to the release-policy gate above.
6. Track the physical column/index drop as a separate later contract change after reader/rollback retirement. Do not mark it complete or make it an unchecked implementation task that prevents this runtime cleanup from finishing.
