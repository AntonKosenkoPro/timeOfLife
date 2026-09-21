# Track settle polish

Fix the Start→Stop visual settle on real devices: the running swap waited on
a fixed delay that a slow keyboard slide could outlast, the tag branch
unmounted when idle (so the below-button slot still changed height whenever
tags were taller than Recents), and `PrimaryButton` ran its own 0.15 s
crossfade on every swap. All three made Stop bubble up from the bottom on
device even though each looked fine in isolation on the simulator.

## Why

User-tested on iPhone (video + device log timestamps): with real categories
the tags panel is taller than Recents, so the slot grew ~45 pt at swap time;
the fixed 350 ms wait lost to a ~404 ms device keyboard slide; the button
tint/label crossfaded inside the dismissal transaction. Each fix is verified
by the new behavior: tap → haptic + resign, keyboard slides with Start still
shown → instant cut to Stop in place.

## What changes

- `timer-capture-experience` (MODIFIED × 3): refresh-on-return for
  Recents, keyboard-deferred Start swap, instant no-animation swap, and
  both-branches-mounted slot invariance. No new surfaces, no contract
  changes; all scenarios are already implemented and covered by
  `TrackViewModelTests` (defer, cancel, inherit-after-reload) plus
  frame-level simulator verification.
