## Context

See proposal.md (Why). Current state: `TrackContent.primaryDisabled`
returns `!vm.canStart` for idle/ready/saved, and the name draft still
holds text during `.saved`, so Start renders enabled while `start()`
(which guards on `.ready`) silently ignores taps — for the ~1.6 s until
`scheduleSavedReset` returns to ready.

## Goals / Non-Goals

**Goals:** make the non-startable saved window visible using the existing
dimmed-disabled language (same as idle-with-empty-text).

**Non-Goals:** changing the confirmation duration, making saved-state taps
start immediately, touching other states' enablement, accessibility-label
changes beyond the standard `disabled` trait.

## Decisions

- **Disable via the existing `primaryDisabled` switch** (add `.saved: true`
  alongside the `.saving` arm) rather than gating inside `start()` or the
  button action: enablement is purely a view concern already centralized
  there, and `PrimaryButton` already dims + ignores taps when disabled.
  Alternative considered — start-immediately-on-tap during saved — rejected:
  risks accidental restarts from reflexive double-taps after Stop.
- **No ViewModel change**: `start()`'s `.ready` guard stays as the safety
  net; the fix only aligns the rendered signal with it.

## Risks / Trade-offs

- [Risk] A fast Stop→Start sequence now visibly waits out the 1.6 s
  confirmation instead of silently swallowing the tap → accepted: honest
  signal was the point of the change; the window is unchanged in length.
- [Risk] Existing tests asserting saved-state enablement → checked during
  implementation; expectations updated to dimmed.

## Migration Plan

None (local UI-only change, no data or contract impact). Rollback: revert
the one case arm.
