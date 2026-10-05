# Tasks: profile-as-page

## 1. Reproduce (recorded, on current tree) — DONE

- [x] 1.1 Record the Profile→Categories push on simulator (populated list): glass `+` stretches to a blurry pill mid-push, glyph pops into the settled circle a beat late (video + extracted frames).
- [x] 1.2 Confirm the same smear on History→entry push (system back `<` + trailing `✓` smear identically) — proves platform behavior, out of scope for this change.

## 2. Implement

- [x] 2.1 `AppShellView`: replace `.sheet(isPresented: $isShowingProfile, onDismiss:)` with per-tab `.navigationDestination(isPresented: $isShowingProfile)`; add `.onChange(of: isShowingProfile)` true→false → `trackVM.load()` (exit reload).
- [x] 2.2 `ProfileView`: remove inner `NavigationStack`, Done toolbar, `dismiss` env; keep title/rows/ids/`NavigationLink`; wrap preview in `NavigationStack`.
- [x] 2.3 Remove `L10n.profileDone` (en + ru + `LocalizationTests` snapshot) after grep-confirmed dead.
- [x] 2.4 Re-check FURPS rows + `Design/` screens for sheet-based Profile wording; fix conflicts.

## 3. Verify

- [x] 3.1 `swiftlint lint --strict`, build, full `xcodebuild test` green (docs/ios-test-loop.md).
- [x] 3.2 Record the new flow (Track → Profile push with `<` back, no Done → Categories push → editor still sheet → back to Track with fresh data) and compare against the 1.1 repro.
- [x] 3.3 `openspec validate --all`.
