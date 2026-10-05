# Design: profile-as-page

## Decisions

1. **Per-tab destination, not a shared path.** Each tab's `navigationRoot` gets
   `.navigationDestination(isPresented: $isShowingProfile)` reusing the
   existing shell-level flag (History's `navigationDestination(item:)` is the
   precedent). No shared `NavigationPath` type, no AppShellViewModel change —
   the Profile button keeps calling the same `onProfile` closure.
2. **Exit reload via bool flip, not `onDisappear`.** `navigationDestination(isPresented:)`
   flips the bool false on pop — `.onChange(of: isShowingProfile)` (true→false)
   replaces the sheet's `onDismiss: trackVM.load()` with identical once-on-exit
   semantics (pushes to Categories don't touch the flag, so no spurious reloads).
3. **Strip `ProfileView`'s inner stack.** Remove its `NavigationStack`, Done
   toolbar, and `dismiss` env; keep title, sections, rows, identifiers, and the
   `NavigationLink` to Categories (now pushes on the tab stack). Preview wraps
   in a `NavigationStack` for chrome.
4. **`L10n.profileDone` removed** (en + ru + snapshot) — dead string, no other
   caller. Verified by grep before removal.

## Risks

- **Push morph unchanged (accepted non-goal).** Profile→Categories remains a
  push, so the iOS 26 glass toolbar-item interpolation persists — proven
  platform behavior (History→entry smears identically). This change buys
  navigation consistency, not animation relief.
- **Tab state on return.** Popping restores the tab view as-is (same as sheet
  dismissal); Track data reload covers freshness. No `selectedTab` churn
  (the StateObject guard in `AppShellView` is untouched).
- **No ctx7 needed:** pure SwiftUI navigation, no external dependency.
