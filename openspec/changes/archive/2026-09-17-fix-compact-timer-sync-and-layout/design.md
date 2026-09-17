# Design: Compact-Timer Sync & Small-Screen Layout Fixes

## Context

See `proposal.md` (Why) for motivation. All three defects are root-caused in current code (read-only investigation, no behavior changed yet):

- **Bug 1**: `TrackViewModel.load()` (`Features/TimeTracking/ViewModels/TrackViewModel.swift:53`) only transitions *into* `.running` when a persisted timer exists — it never leaves `.running` when the timer is gone. `AppShellViewModel.stopFromCompact()` stops via the service and nils the shell's `runningTimer`, but Track's `state` stays `.running` with its 1 s ticker counting `elapsed` forever. Returning to Track re-runs `load()` (`.task` on appear), which sees no persisted timer and touches nothing. Second facet: `beginRunning` disables the idle timer and only `stop()` re-enables it, so the externally-stopped Track also keeps the screen awake indefinitely.
- **Bug 2**: `LogTimeView.timeRow` embeds `.graphical` / `.wheel` `DatePicker`s directly in the card `VStack`. Both styles carry a large intrinsic width (~320 pt+); on a 320 pt screen the expanded picker stretches the `ScrollView` content wider than the viewport, so every card goes full-bleed and labels/values clip at the screen edges (per the attached screenshots). The existing `.clipped()` on the picker container clips rendering, not layout width.
- **Bug 3**: `CompactTimer` pads horizontal + top but not bottom inside the `.safeAreaInset(edge: .bottom)` slot, so the surface sits flush (1–2 px overlap read) against the tab bar.

## Goals / Non-Goals

Goals: three minimal, independently verifiable fixes with unit coverage where the logic is testable (bug 1) and simulator verification where it is layout (bugs 2, 3).

Design-level non-goals: no `timer_state` / `TimerService` API changes; no LogTime visual redesign; no new strings.

## Decisions

### D1: Reconcile in `TrackViewModel.load()`, scoped to `.running`
After the existing catalog + persisted-timer load, when `state` is `.running` yet `runningTimerState()` is nil (or its activity id is unresolvable): stop the ticker, set `isIdleTimerDisabled = false`, reset `elapsed` to zero, and set `.ready(activity)` when `store.activity(id:)` still returns the activity, else `.idle`.

*Alternatives considered*: transitioning to `.saved` with a confirmation (rejected — the saved duration isn't known without an extra latest-entry fetch; `.ready` is honest and matches the post-save reset destination); refetching the just-saved entry to show `.saved` (rejected — extra query for a transient confirmation nobody asked for); observing the service reactively from Track (rejected — larger machinery; appear-time reconciliation covers every path that reaches Track, which is the only place the stale state is visible).

*Scope note*: `.saving` / `.error` are deliberately untouched — they are mid-flight own-stop states that self-resolve through their async paths, and `load()` re-running mid-save sees either a still-present timer (no reconcile) or an already-completed save (state already `.saved`, not `.running`, so no clobber).

### D2: Bound the inline pickers to the card width
Constrain the expanded `DatePicker` to the offered card width (e.g. `.frame(maxWidth: .infinity)` on the picker inside the already-`.clipped()` container) for both `.graphical` and `.wheel` styles, so intrinsic width never stretches the scroll content past the viewport. The wheels compress (glyphs may tighten) but the cards keep their `Theme.spacingMedium` margins and nothing clips at the edges.

*Alternatives considered*: switching picker styles on compact screens (rejected — breaks the established Calendar grammar the manual-entry spec mandates); embedding pickers in a horizontal `ScrollView` (rejected — hides content instead of fitting it); fixed 320 pt-point hardcoding (rejected — `maxWidth: .infinity` adapts to every size class).

### D3: Bottom pad the compact timer inside its own view
Add `.padding(.bottom, Theme.spacingExtraSmall)` (mirroring the existing top pad) inside `CompactTimer`, so both History and Insights insets gain the gap from one place with no call-site changes.

*Alternative considered*: padding at the `safeAreaInset` call sites (rejected — two places to keep in sync for one surface).

## Risks / Trade-offs

- [Risk] Reconcile-then-save race: own-stop in flight (`.saving`) while `load()` re-runs → Mitigation: reconcile touches `.running` only; `.saving` completes to `.saved` normally afterward.
- [Risk] Wheel picker compressed below comfortable legibility on 320 pt → Mitigation: wheels degrade by tightening, not by clipping content; verified visually on the SE-1st-gen-class simulator in all three form modes (CREATE/EDIT/LOCKED) × both picker kinds.
- [Risk] Extra bottom pad looks floaty on large screens → Mitigation: `spacingExtraSmall` (4 pt) matches the existing top pad; symmetric and minimal.

## Migration Plan

None. No schema, defaults, or persisted-data changes. Rollback per fix is a revert of a view-model branch / modifier / padding line.

## Open Questions

None — all three defects are root-caused above with reproduction paths in tasks.
