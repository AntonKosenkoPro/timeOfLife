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

5. **Categories `+` glyph: fix deferred, code left clean (issue #101).**
   Six rounds investigated, all device-checked except the probe rounds:
   `glassEffectTransition` (system toolbar glass ignores it), conditional
   transaction, semantic placement, constant `ToolbarItem(id:)`, own
   circular glass + hidden shared background (separation gone, whole
   button late instead), `.transition(.identity)` on the glyph (works in
   probe frames, previous behavior returns on device). A throwaway
   `ToolbarProbeView` harness (reverted) proved via frame captures that the
   bare construction reproduces the empty-circle phase — pure iOS 26
   system morph, not app churn. Per owner decision 2026-10-06 the code
   stays exactly as before these rounds (positional placement, no id,
   unconditional sheet-highlight transaction) and the remaining work is
   tracked in #101. Visual-only investigation: no behavior, destination,
   `vm.addCategory()`, sheet, id, or string changes at any point.
   ctx7: SwiftUI `/websites/developer_apple_swiftui` — `glassEffectTransition`
   and `ToolbarItemPlacement` docs; web: SO 79749310 (stable-id morph),
   SO 79771028 (shared-background flicker fix), SO 79912994 (custom glass
   button for full transition control).

## Risks

- **Push morph unchanged except the Categories `+` glyph.** Profile→Categories
  remains a push; only the `+` button moves to the semantic `.primaryAction`
  placement (same trailing spot) so its glass isn't re-morphed on push. The
  History→entry `✓` smear is still platform behavior (out of scope). This
  change buys navigation consistency plus the one glyph fix, not general
  animation relief.
- **Tab state on return.** Popping restores the tab view as-is (same as sheet
  dismissal); Track data reload covers freshness. No `selectedTab` churn
  (the StateObject guard in `AppShellView` is untouched).
- **No ctx7 needed:** pure SwiftUI navigation, no external dependency.
