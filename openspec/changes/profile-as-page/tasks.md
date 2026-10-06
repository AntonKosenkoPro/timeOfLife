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

## 4. Fix Categories `+` glyph delay on push (issue #101 follow-up)

- [x] 4.1 Diagnose from the 1.1 frames: mid-push the toolbar shows an empty glass circle; the `+` glyph fades in a beat after the push settles (Liquid Glass matched-geometry toolbar morph animates glass and content separately). The existing `.transaction { disablesAnimations = true }` (sheet highlight calm) covers the glass, not the glyph transition.
- [x] 4.2 Round 1: keep the transaction, add `.instantToolbarGlass()` → `glassEffectTransition(.identity)` on iOS 26+ (no-op pre-26). Result 2026-10-06: glyph still late on device — system toolbar glass ignores the modifier. Round 2: transaction conditional on `vm.isShowingEditor` (sheet calm preserved by construction, push path untouched). Result 2026-10-06: glyph still late — transaction ruled out. Round 3: `ToolbarItem` placement `.navigationBarTrailing` → `.primaryAction` (same trailing spot on iOS; mirrors EditorToolbar's semantic placements). Result: glyph still late — placement ruled out. Round 4: constant `ToolbarItem(id:)` per SO 79749310. Result: glyph still late — the id only matches source↔destination pairs (Files keeps the same button on both pages); our source has no trailing item, so the destination item still materializes. Round 5: `ToolbarProbeView` harness (throwaway, reverted) proved it on simulator frame captures — the BARE construction reproduces the empty-circle phase, so it's pure system morph, not app churn. Fix shipped: hide the morphed shared background + own glass circle — device result: separation gone, but the whole button now arrives late as one unit. Round 6: probe A/B/C in one build — `.transition(.identity)` on the glyph (A) and on the button (B) both remove the separation with system glass intact in probe frames; own-glass-no-id (C) also arrives as one unit. Shipped A — device result: previous behavior came back (empty circle → late glyph). DECISION 2026-10-06: stop here; code reverted to the pre-rounds state (unconditional sheet-highlight transaction, positional placement, no extras). Remaining tracked in #101. No behavior change: same destination, same `vm.addCategory()`, same sheet, same ids/strings.
- [ ] 4.3 Record Profile→Categories push at default speed and confirm the `+` is present with the glass (no empty-circle frame); re-record Categories `+`→editor sheet open to confirm the press-highlight calm still holds. (Blocked 2026-10-05: host touch injection dead — taps + Home ignored on both booted sims while screenshots/describe work; needs a retry or an on-device check.)
- [x] 4.4 `swiftlint lint --strict` clean, simulator builds warning-free, full `xcodebuild test` green except pre-existing midnight flake (`HistoryViewModelTests.loadsAndResolvesCategories` uses `timeIntervalSinceNow`, splits across two days 00:00–02:00 local — fails on any tree, unrelated to this change; all other 543 tests / 53 suites green), `openspec validate --all` 22/22.
