## Why

History day-group headers render as an opaque slab (`Theme.backgroundPrimary`) directly under a transparent Liquid-Glass navigation bar. On iPad the pinned slab spans the full pane width, so the nav→content transition reads as two competing "tops" and the entire History layout feels broken (issue #35). iPhone shows the same mismatch at smaller scale.

## What Changes

- History sticky day headers stop being opaque: pinned and in-list headers share one continuous translucent treatment with the navigation bar (system material + scroll-edge effect), Calendar-Agenda-like.
- The exact winning treatment (material, soft-vs-hard edge style, header typography scale) is decided by three throwaway spikes run on-device (iPhone + iPad landscape, light + dark, Reduce Transparency) before implementation.
- Elevation-gated day total ("2h 35m tracked" only when pinned) is preserved unless the spikes prove the native-`List` option wins, in which case the total moves to an always-visible home (decision recorded in design.md).
- No new strings, no data or API changes, no behavior changes outside History headers.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `history-entry-list`: day-group header background/material requirement changes (opaque → translucent material + scroll-edge effect, continuous with the nav bar); iPad pane-width continuity requirement added. All other requirements (relative-then-absolute labels, elevation-gated total, column alignment) unchanged.

## Impact

- iOS only: `Features/AppShell/Views/HistoryView.swift` (header background + edge-effect style), `Core/Design/Components/SectionHeader.swift` (only if the Calendar-grammar typography option wins), `Design/SCREENS/History.md` + `Design/COMPONENTS.md` docs.
- No backend, OpenAPI, or persistence impact. No new dependencies.
- External docs fetched (ctx7 `/websites/developer_apple_swiftui`): `scrollEdgeEffectStyle`, `Material ultraThinMaterial toolbar background`, `pinnedViews LazyVStack section headers`; iOS 18 floor, Liquid-Glass behavior observed on iOS 26.

## Non-goals

- Per-header `.glassEffect()` capsules (glass is the controls layer, never the content layer; re-samples every scroll frame).
- Migrating History to native `List` unless the spikes justify it (tracked as spike B, decision-gated).
- Readable-width (`maxContentWidth`) iPad reflow — secondary to the material break, deferred to a follow-up.
- New localization keys or VoiceOver grammar changes.
