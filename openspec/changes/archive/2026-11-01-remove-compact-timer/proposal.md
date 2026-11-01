## Why

The in-app compact timer adds a visually heavy second control layer above the tab bar on History and Insights, competing with their browsing content. The owner has chosen removal rather than another visual variant: Track remains the dedicated in-app timer surface, while existing Live Activities remain optional system surfaces.

## What Changes

- **BREAKING (UI contract):** Remove the compact timer from History and Insights, including its return-to-Track target and direct Stop action. Users select Track to inspect or stop a run inside the app.
- Add no replacement strip, badge, toolbar timer, running indicator, or preference. Do not reserve the deleted card's space.
- Preserve the running draft, elapsed-time anchor, crash recovery, Track controls and feedback, and existing Live Activity presentations and Stop/return links. Removal must work equally when Live Activities are disabled or Dynamic Island is unavailable.
- Remove compact-only view-model plumbing, polling, accessibility helpers, and unused presentation resources, without deleting shared Track/Live Activity strings or weakening entry refresh and external-stop reconciliation.
- Revise the current contracts and design documentation that require the compact timer; explicitly supersede Design decision D29's requirement for persistent off-Track timer visibility.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `app-shell`: Replace mandatory off-Track timer visibility/stoppability with timer-free History/Insights and ordinary navigation back to Track; scope shell accessibility to remaining navigation.
- `history-entry-list`: Remove compact-timer visibility and inset requirements while preserving committed-only rows, final-row reachability, the persistent navigation bar, and entry refresh after saves.
- `insights-breakdown`: Remove compact-timer presentation from the committed-only breakdown contract; preserve aggregation and refresh after saves.
- `timer-capture-experience`: Remove obsolete compact-stop wording while retaining reconciliation whenever the persisted draft has ended through another existing path.

## Impact

- iOS: `CompactTimer.swift`, shell hosting and compact-only state/polling, History/Insights refresh wiring, compact-only tests and resources. Keep timer storage, save semantics, sync, per-tab navigation, and Live Activity implementations intact.
- Documentation at implementation: `Design/COMPONENTS.md`, `Design/SCREENS/{AppShell,TimeTracking}.md`, `Design/INTERACTIONS.md`, `Design/DECISIONS.md` (supersede D29), `Design/README.md`, `docs/project-context.md`, `docs/history-roadmap.md`, applicable manual-testing/README references, `AGENTS.md`'s scope summary, and `openspec/config.yaml`. Baselines are updated through delta sync/archive, never edited directly during implementation.
- Requirements: retain Timetracking F1/F2/F4/R2 (local-first persistence and save), F15 (Live Activities), and Common minimalism/accessibility/localization/verification rules. No FURPS row requires the compact timer. F12's deferred ControlWidget is not a replacement.
- No backend, OpenAPI, database-format, deployment-floor, dependency, or authentication change. No new tracking UI, notifications, settings, or redesign of Track/system surfaces.

### Research

- Topic/HIG: Context7 `/websites/developer_apple_design_human-interface-guidelines`, query `Tab bars: accessory views for ongoing tasks and keeping primary navigation available without unnecessary persistent controls` (2026-11-01). [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars) distinguishes navigation from actions and describes optional accessory presentations; removal is the owner's product decision, not a claimed HIG mandate.
- Apple API: Context7 `/websites/developer_apple_swiftui`, query `iOS 18 SDK via Xcode 16+: onReceive(_:perform:) subscribing to a NotificationCenter publisher to refresh view data when an event arrives` (2026-11-01). [onReceive](https://developer.apple.com/documentation/swiftui/view/onreceive(_:perform:)) supports retaining event-driven refresh using existing app notifications. Compatibility target: iOS 18 SDK via Xcode 16+; no adoption of newer APIs is needed.
- External-library/setup best-practice query waived: no dependency or service changes; only existing SwiftUI/notification and local reload paths are involved. ActivityKit API research waived: its implementation and baseline contract stay unchanged; Live Activities remain optional, as already specified in `live-activities`.
- Reconfirm research at apply time. The supplied screenshots informed the visual decision; no screenshots or other binaries are stored in this change.
