## Why

The current timer screen and design study do not express a coherent product journey: navigation is auth-gated, the primary timer lacks meaningful states, and planned review and insight features have no durable place in the information architecture. The app needs a local-first shell and a capture flow that make starting a timer immediately understandable while scaling to History, Insights, system surfaces, and macOS.

## What Changes

- Replace the timer-only root with three primary destinations: Track, History, and Insights.
- Put account, sync, catalog management, integrations, export, appearance, and destructive controls behind a profile destination rather than a primary tab.
- Redesign Track around a centered numeric timer readout whose only purpose is displaying the exact duration while the user chooses, starts, or stops an activity.
- Make recent activities select-first: tapping a recent activity prepares it, and an explicit Start action begins timing.
- Keep a running timer visible and stoppable while browsing History or Insights through a compact persistent timer surface.
- Define empty, activity-selection, ready, running, and saved states for the Track flow, including contextual first-use guidance without a blocking onboarding carousel.
- Keep concrete Activities separate from optional analytics Categories: capture chooses Activities by name, while category management and assignment live outside the capture surface.
- Establish a navigation model that maps from iOS tabs to a future macOS sidebar without changing the product hierarchy.
- Remove placeholder `Today` and `Recent` semantics from the timer study; daily review belongs to History, while the root capture destination is named Track.

## Capabilities

### New Capabilities
- `app-shell`: Primary Track, History, and Insights navigation; profile-owned secondary destinations; persistent running-timer access; and equivalent macOS hierarchy.
- `timer-capture-experience`: Activity selection and creation, recent-activity preparation, numeric timer states, start/stop/save feedback, and first-use capture guidance.

### Modified Capabilities
<!-- None — openspec/specs/ is empty and the related local-first capabilities remain in their own active change. -->

## Impact

- **iOS app**: root navigation, timer screen/view model, activity chooser, compact running-timer surface, profile destination, History and Insights placeholders, localization, accessibility, and haptics.
- **Design system**: screen specifications, navigation rules, numeric timer semantics, component states, motion, light/dark appearance, and system-surface continuity.
- **Future macOS app**: establishes the hierarchy that will map into sidebar navigation; no macOS implementation is included in this change.
- **Architecture**: depends on the local-first store and persisted running-timer state described by `local-first-sync-architecture`; it does not alter backend APIs.
- **Tests**: view-model/state-transition tests, navigation tests, accessibility coverage, warning-as-error build, and simulator flow verification.
