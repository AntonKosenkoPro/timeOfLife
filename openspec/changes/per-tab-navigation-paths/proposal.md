## Why

After `profile-as-page`, Profile and every nested destination (Manage Categories, entry form, NamePicker) are pushes inside per-tab `NavigationStack`s — but the tab bar stays visible on all of them, and one shell-level `isShowingProfile` flag drives the Profile destination on all three stacks at once. The result reads as parallel navigation stacks fighting each other: tabs on pages that should be pages, and phantom Profile pushes on tabs the user never opened it from.

## What Changes

- Each tab owns its navigation path (Track / History / Insights keep independent push state); opening Profile on one tab never pre-pushes it on the others.
- The shared `isShowingProfile` bool is replaced by per-tab path state (typed shell route: Profile, plus existing History entry-form and Track/History NamePicker pushes expressed in the same path where practical).
- Pushed destinations past the tab root hide the tab bar, so Profile, Manage Categories, the pushed entry form, and NamePicker present as pages with system Back — no tab-switch-while-pushed.
- Popping back to a tab restores that tab's prior state; Track data reload on Profile exit is preserved (per-tab, once-on-exit — not global).
- Auth navigation (`container.navigation` / `AppNavigationStack` + `AppRoute`) stays untouched: auth-only, cleared on sign-out.

**Non-goals:** no new destinations or rows; no change to Profile content, sync, sign-out, erase, or category editor (stays a sheet); no Liquid Glass push-morph work (accepted platform behavior per `profile-as-page`); no global single-path merge of tab state; no deep-link / state-restoration support beyond keeping per-tab state independent.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `app-shell`: per-tab navigation paths replace the shared Profile flag; tab bar hidden on pushed destinations; per-tab Profile exit restores tab state + reloads Track data.

## Impact

- `AppShellView` (shared flag → per-tab paths, `NavigationStack(path:)` per tab, tab-bar hiding on destinations), `AppShellViewModel` (selected tab + per-tab path ownership), `ProfileView` (no logic change — push target moves into path), `HistoryView` (entry-form `navigationDestination(item:)` folds into History path), `TrackContent` / `LogTimeView` NamePicker links (fold into owning tab path where practical).
- Accessibility: tab bar no longer exposed on pushed pages; system Back remains the exit; existing identifiers (`TabTrack/History/Insights`, `Profile`, `ProfileCategoriesRow`, entry-form ids) unchanged.
- No backend, OpenAPI, FURPS-behavior, or string changes. No new dependencies — pure SwiftUI navigation, no ctx7 fetch needed (same rationale as `profile-as-page`).
