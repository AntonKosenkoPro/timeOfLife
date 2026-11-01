## Context

See `proposal.md` for the motivation and agreed product boundary. This design is needed because deleting the view alone leaves compact-only polling and entry-refresh coupling behind.

`AppShellView` adds `CompactTimer` through a bottom safe-area inset on History and Insights. `AppShellViewModel` polls the persisted draft once a second; its published text also supplies both destinations' `refreshSignal`. The compact view has its own elapsed-time timeline. Thus the shell poll serves draft-change detection and refresh, not the authoritative running timer.

Track independently owns its running presentation and reconciles with the persisted draft. Existing foreground/tab-return/URL/sync paths reload Track. Live Activity Stop links select Track and save through its existing stop path; the extension's existing fallback stop signal is bridged by `AppContainer` to `.timerStoppedExternally`. These mechanisms and their cold-open behavior must remain intact.

Constraints: LocalStore stays the sole mutation chokepoint; D8/F4/R2 timer persistence and F2 transactional saves stay unchanged; D28's stable Track controls stay unchanged. This change intentionally supersedes Design D29, not the independent Live Activity contract or its optional availability.

## Goals / Non-Goals

**Goals:**
- Delete the compact view and its exclusive state, resources, and recurring work.
- Decouple committed-entry refresh from the deleted visual surface without changing sync triggers or aggregates.
- Preserve existing layout, navigation paths, accessibility, and external-stop reliability outside the removed surface.

**Non-Goals:**
- No replacement timer UI, preference, native tab accessory, or new timer/entry architecture.
- No changes to `TimerService` save semantics, LocalStore formats, Live Activity rendering/intents/links, authentication, backend, or OpenAPI.
- No general notification framework, storage observation layer, or broad concurrency refactor.

## Decisions

### 1. Remove the entire accessory instead of hiding or restyling it

Delete `CompactTimer.swift`, both bottom inset call sites, and the shell's compact-view builder. Retain only normal system tab-bar safe-area behavior; do not substitute a spacer, background band, badge, or setting. Keep per-tab navigation paths, title/toolbars, and push-driven tab-bar visibility unchanged.

Alternatives rejected: a one-line strip still adds a persistent control layer; a tab indicator is a replacement the owner did not choose; a visibility setting retains implementation and testing complexity for a rejected surface. A native accessory would require a different design plus OS-specific behavior and is out of scope.

### 2. Remove compact-only polling, preserve refresh through existing events and lifecycle

Remove `AppShellViewModel.runningTimer`, its compact Stop/load/ticker APIs and ticker ownership after checking their references, plus shell subscriptions/task calls used exclusively to drive them. Keep the shell view model's navigation responsibilities and all Track reload/deep-link handling. Remove the `refreshSignal` parameters from History and Insights rather than keeping an unused compatibility API.

Before deleting the poll, wire History/Insights refresh to existing external-stop and foreground events using their established invalidate/reload paths. Use `.timerStoppedExternally` for the existing fallback stop path and foreground invalidation to cover saves while suspended or missed notifications. Retain on-leave invalidation/on-appear reload for normal Track saves, and preserve direct sync-exit reloads. Existing Live Activity Stop links still select Track, so returning to a browsing tab uses its normal re-entry reload; do not alter URL routing to keep the previous tab selected.

Event handlers request local snapshot reloads only, not sync, and use the existing guarded/serialized loading behavior. In History retain undo registration and pull-notice behavior by routing refresh through its established reload helper. In Insights preserve period and lens state. Repeated foreground/sync/stop events must not blank the last good snapshot or create uncontrolled overlapping reloads; cover the resulting wiring with focused tests rather than relying only on view-model aggregate tests.

Alternatives rejected: retaining the one-second shell poll just for freshness leaves unnecessary timer-related work; removing every refresh trigger would regress locally saved entries. Introducing a new global event bus is disproportionate to two existing consumers.

### 3. Preserve external-stop reconciliation and all shared copy

Keep Track's existing reconciliation, elapsed ticker, idle-timer management, foreground/tab-return reloads, and cold/warm Live Activity Stop URL handling. Update stale compact-specific comments, not their behavior. A draft that disappears through an existing stop path must never leave Track ghost-running.

Delete only proven compact-exclusive resources:
- `Theme.opacityAccentFaint`, currently used solely by the removed icon disc.
- `TrackState.compactAccessibilityLabel` and its dedicated test, which have no production consumer outside the retired surface's concept.
- `timer.compactReturnHint`, its `L10n` member, all five locale entries, and localization snapshot entry.

Keep `timer.compactRunning` and `timer.compactStop`: despite their names, the full Track readout and/or shared Live Activity core still use them. Do not rename shared keys as part of this removal. Keep the widget extension bundles and their localized accessibility intact.

Retire tests for deleted compact-only APIs, not tests of the underlying stop/save/reconciliation behavior. Add checks for timer-free shell composition and preserved refresh wiring; do not claim that deleting tests for removed functionality improves retained behavior coverage.

### 4. Make the contract reversal explicit

The `app-shell` delta removes mandatory global in-app timer access and adds explicit timer-free History/Insights. History retains its persistent navigation bar under a renamed requirement and its final-row reachability without the card inset. History/Insights continue to exclude uncommitted runs and show newly committed entries. `timer-capture-experience` retains the full stable-stop requirement with the obsolete compact trigger generalized to other existing stop paths. `live-activities` needs no delta.

At implementation, remove the component's current design contract, update affected screen checklists/interactions/indexes, and mark D29 superseded with the new rationale: global state need not occupy every tab; focused browsing is prioritized over in-app off-Track glanceability. Update current scope/roadmap/testing summaries but leave archived changes as historical records. Review FURPS Common U1–U5/S2/S3/S5–S7 and Timetracking F1/F2/F4/F15/R2; no requirements-row change is expected.

### 5. Research basis and compatibility

- Topic/HIG: Context7 `/websites/developer_apple_design_human-interface-guidelines`, query `Tab bars: accessory views for ongoing tasks and keeping primary navigation available without unnecessary persistent controls`, fetched 2026-11-01; [tab-bar guidance](https://developer.apple.com/design/human-interface-guidelines/tab-bars) keeps tab items navigational and describes optional accessories. It does not mandate this removal or justify changing the tab bar itself.
- Apple API: Context7 `/websites/developer_apple_swiftui`, query `iOS 18 SDK via Xcode 16+: onReceive(_:perform:) subscribing to a NotificationCenter publisher to refresh view data when an event arrives`, fetched 2026-11-01; [onReceive](https://developer.apple.com/documentation/swiftui/view/onreceive(_:perform:)) performs an action for publisher emissions and is available below the iOS 18 floor. Use existing app notification publishers; no newer API or deployment change.
- Compatibility target is iOS 18 SDK via Xcode 16+, with visual checks on iOS 18 and iOS 26+. Context7 returned current indexed docs rather than a separately versioned SDK corpus; verify the target build at apply time.
- ActivityKit API query waived because its code/contract are unchanged. External-library/setup query waived because no dependency/service/setup changes are introduced. Reconfirm this research before implementation.

## Risks / Trade-offs

- [Runs are less visible while browsing, especially without Live Activities] → Accepted product trade-off; Track remains the reliable control surface, with no hidden assumption that a system timer is always visible.
- [Stopping from a browsing tab takes an extra navigation action] → Accepted; do not recreate a Stop shortcut elsewhere.
- [Removing polling makes committed data stale] → Replace its refresh role first using existing stop/foreground and re-entry paths; test return-from-Track, visible fallback external stop, background return, and sync independently.
- [Shared localization is deleted because its key says compact] → Verify production references across app and extensions; retain shared Stop/running keys and five-locale coverage.
- [Deleted inset breaks final-row reachability or leaves a blank band] → Compare running versus idle History/Insights at small sizes, both appearances, large text, iOS 18 and iOS 26+; normal tab-bar safe-area behavior remains.
- [External stop leaves Track stale] → Retain existing reconciliation and Live Activity lifecycle tests, including cold-open Stop; do not delete regression guards with the compact view.

## Migration Plan

1. Before implementation, fetch/rebase onto fresh `origin/main`, reconfirm research, and capture the current compact layout and save/refresh behavior as a reference outside git. This is a deliberate product removal, not an unproven bugfix.
2. Introduce/test retained event-driven refresh, remove compact UI and exclusive resources/plumbing, and update current design/documentation references in this worktree. No database migration, data reset, or backend deployment is needed.
3. Run spec validation and both platform verification suites per repository rules (backend and iOS checks on separate agents; serialize Xcode builds). Perform the visual/lifecycle checks in `tasks.md`; do not commit capture binaries.
4. Rebase again before PR and repeat affected checks. Baselines remain untouched until delta sync/archive through the normal review workflow.
5. Rollback, if needed, is a normal forward revert of the app removal and its contracts. Existing persisted runs remain readable because storage and save formats do not change.
