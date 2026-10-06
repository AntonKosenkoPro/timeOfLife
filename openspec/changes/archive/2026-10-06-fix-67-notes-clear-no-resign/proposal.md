## Why

The shipped notes-× fixes both fail the actual requirement (issue #67: clearing Notes must keep the keyboard open, FURPS Timetracking F13). The `main`-merged B1 touch-down suppress flag never suppresses on real taps (recorded repro), and its async-refocus replacement lets the keyboard visibly dismiss and reappear — a flicker compromise the requirement forbids. The root cause is structural: `FormCard`'s blanket *simultaneous* tap resigns focus for every tap inside the card, including the ×, so any fix that keeps it must race or mask the resign.

## What Changes

- `FormCard`'s tap-away gesture downgrades from *simultaneous* to plain `.onTapGesture`: taps on labels/padding/background still resign; taps consumed by child buttons no longer reach it.
- Each interactive child that must dismiss the keyboard resigns explicitly at its own call site: the name-row `NavigationLink` (scoped simultaneous tap), `TagSelector` toggles, and the start/end picker pills (via `toggle(_:)`).
- The Notes × action goes back to clearing only (`vm.clearNotes()`); the B1 suppress machinery (`suppressNextResign` binding, `@State` flag, zero-distance drag) and the async refocus are removed — the resign never fires, so there is nothing to race and no flicker.
- No behavior change for tap-away dismissal, chip/pill dismissal, TextField focus, the #42 visibility rule, or any other × site.

**Non-goals:** push-transition toolbar animation (issue #101, accepted platform behavior).

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `entry-editor`: the Notes-row clear keeps the keyboard open with no dismiss/reappear flicker; tap-away and control-tap dismissal preserved as specified.

## Impact

- `FormCard.swift` (gesture semantics + contract comment), `LogTimeView.swift` (4 explicit resign sites + × simplification).
- Supersedes unmerged PR #117 (async-refocus approach) and the archived B1 design — close #117 unmerged on ship.
