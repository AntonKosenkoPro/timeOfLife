## Context

#112 shipped a touch-down one-shot suppress: the notes `×` armed `suppressNextResign` in a zero-distance `DragGesture.onChanged` (touch-down), and the card's simultaneous `TapGesture.onEnded` skipped one resign when the flag was set. The design assumed touch-down handling always precedes every touch-up handler for the same touch. Device verification of the follow-up repro proved that assumption false for real finger taps: the drag's `onChanged` is not guaranteed to be delivered ahead of the tap's `onEnded` on-device, so the flag is not reliably armed when the card gesture fires — the keyboard dismisses and #67 reproduces. The simulator repro used for #112 did not surface this because synthetic taps deliver the gesture callbacks in a friendlier order.

## Goals / Non-Goals

**Goals:**
- Tapping the notes `×` clears the draft notes and deterministically leaves Notes focused with the keyboard open, on simulator and device.
- Remove the unreliable touch-down flag machinery entirely (no stale-suppress windows, no gesture-ordering dependence).
- Keep every other tap in the card resigning exactly as today.

**Non-Goals:**
- No changes to Name-row clear, chips, pickers, or any other focus behavior.
- No new dependencies, strings, or API.

## Decisions

- **D1: Re-claim focus after touch-up instead of suppressing resign on touch-down.** The card's simultaneous tap gesture and the button action both run at touch-up in an unspecified relative order, so any synchronous claim-or-suppress at touch-up races. `DispatchQueue.main.async { focusedField = .notes }` enqueues strictly after all touch-up handlers for the current touch, making `focused` the deterministic final state regardless of their order. *Alternative considered*: keep the flag but arm it in more places (e.g. `onAppear`, focus change) — rejected; arming earlier widens the stale-suppress window (a cancelled tap would eat a later legitimate resign) without fixing the root ordering hazard.
- **D2: `FormCard` goes back to an unconditional resign.** With the re-claim owned by the notes `×` action itself, the card needs no knowledge of any exception: one code path, no binding, no one-shot state to leak between taps. Chip/card taps resign exactly as before this whole episode.
- **D3: No animation or delay tuning.** The async hop is one main-queue turn — imperceptible, no flicker observed on simulator or device. A fixed delay (e.g. `asyncAfter`) would add a visible keyboard dip on the paths where the resign lands first; the plain async re-claim re-asserts focus before the keyboard animates away.

## Risks / Trade-offs

- [A cancelled tap (press `×`, slide off, release elsewhere) clears nothing but still re-claims focus] → Accepted; the old flag had the symmetric wart (a stale suppress eating the next resign). Re-claiming focus on a no-op tap is the milder failure — the keyboard stays where the user already was.
- [Two rapid `×` taps enqueue two async re-claims] → Benign; both set the same value.
- [Device keyboard-animation timing could differ across iOS versions] → Mitigated by device verification on the current release; the mechanism (main-queue ordering, not timing) is version-independent.

## Migration Plan

Single PR onto `main`. Rollback = revert the PR (restores the #112 suppress mechanism, which keeps #67 open on device). No data, schema, or API involvement.
