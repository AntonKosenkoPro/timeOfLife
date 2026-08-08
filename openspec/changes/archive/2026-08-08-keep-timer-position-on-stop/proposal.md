## Why

The saved-state checkmark currently adds height above the numeric timer after Stop, pushing the timer downward during feedback. The timer should remain visually anchored while the confirmation mark appears so stopping feels stable and intentional.

## What Changes

- Keep the numeric timer at the same vertical position when the saved-state checkmark appears after a successful stop.
- Reserve or overlay the confirmation mark without changing the readout's layout geometry.
- Add focused verification for the ready-to-saved timer transition and retain existing accessibility behavior.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `timer-capture-experience`: Clarify that saved feedback appearing above the readout must not displace the numeric timer.

## Impact

- Affects the SwiftUI layout in `NumericTimerReadout` and its Track-screen presentation.
- May add or adjust focused iOS UI/layout tests.
- No API, persistence, localization, dependency, or backend changes.
