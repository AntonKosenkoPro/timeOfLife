## Why

Users often tap Start after the activity actually began (issue #195: "sometimes you starting the timer after the activity actually started a while ago"). Today the running `started_at` is frozen at tap time with no edit path — the only recovery is Stop, then find the entry in History and EDIT it. A lightweight in-run backdate keeps flow on Track.

## What Changes

- Add a `Started HH:MM` tappable caption under the running numeric timer (reserved slot in all states so Start/Stop never moves — D10).
- Spike all three editor variants as throwaway previews for side-by-side comparison (no persistence wiring):
  - **A — Inline expanding wheel (preferred):** tap caption expands a single `hourAndMinute` wheel in place (~216pt) + optional `[-30][-15][-10][-5]` preset row; tap-again collapses. Same single-open grammar as `LogTimeView` time rows, but one picker, no date card, no End card, no nav chrome.
  - **B — Presets half-sheet:** caption opens a `.presentationDetents([.medium])` sheet with preset offsets + optional wheel + Done.
  - **C — Native `.compact`:** system `DatePicker(.compact)` rendering the caption itself; tap opens the OS time popover anchored to the label.
- Converge on one winner (default: A per user preference) and wire it end-to-end: `TrackViewModel.updateDraftStartedAt`, new `LocalStore` draft-only rewrite, ticker restart, Live Activity re-anchor, CompactTimer follows free.
- Validity gate: `newStart <= now`; future times rejected (confirm disabled). Minute precision (floor, LogTime precedent). Overlap allowed (manual-entry precedent). Draft-local only — no outbox/sync payload change; the Stop-committed entry lands with the earlier `started_at` as if tapped on time.
- Non-goals: no pre-Start custom time ("start with offset" button), no End editing mid-run, no date picker UI (overnight runs show `Started yesterday HH:MM` read-only caption; picker stays time-only — see open question in design), no backend/OpenAPI change, no Recents-order change (Recents read committed entries only).

## Capabilities

### New Capabilities

- None — all behavior extends existing capabilities.

### Modified Capabilities

- `timer-capture-experience`: running timer gains a mutable `started_at` via the `Started HH:MM` caption + one editor variant; elapsed/derived duration recompute live.
- `live-activities`: mid-run start change re-anchors the system timer (`ContentState.startedAt` update, chips unchanged) — analogous to the existing retag refresh.
- `local-first-store`: `timer_state` singleton gains a started-at-only rewrite (draft snapshot, never history); sibling to the existing category/notes rewrites.

## Impact

- iOS only (`Features/TimeTracking`: `TrackContent`, `NumericTimerReadout` slot, `TrackViewModel`, `TimerService`, `LiveActivityService`; `Core/Storage/LocalStore` +1 chokepoint method; `LifioLiveActivityCore` untouched shape — new `startedAt` value only). No `backend/`, no `openapi.yaml` change (relay sees a normal entry at Stop).
- Research bundle (ctx7, pin `iOS 18 SDK via Xcode 16+`): SwiftUI `/websites/developer_apple_swiftui` — `DatePicker displayedComponents hourAndMinute datePickerStyle compact wheel`; HIG `/websites/developer_apple_design_human-interface-guidelines` — `pickers date time picker iOS best practices`; ActivityKit `/websites/developer_apple_activitykit` — `update Live Activity ContentState start date timer`. Backend/best-practice item waived — `LocalStore`-only diff, no relay payload change (Stop path unchanged).
- Invariants preserved: `LocalStore` single chokepoint; Theme semantic colors only; strings in `en`+`ru` + `L10n` (U4); D10 state-invariant geometry; no on-disk migration (pre-release, edit in place).
