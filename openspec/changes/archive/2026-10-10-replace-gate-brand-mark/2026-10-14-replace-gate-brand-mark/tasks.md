## 1. Brand asset

- [x] 1.1 Trim `ic_launcher_monochrome.png` (xxxhdpi, ink bbox x 158–273 / y 155–273 of 432²) to the ink box plus ~12% breathing room and scale to 1x/2x/3x PNGs (see design.md D2 for source path and geometry)
- [x] 1.2 Add `BrandMark.imageset` (with `Contents.json`) to `TimeOfLife/Resources/Assets.xcassets`; confirm no `project.yml` edit or regen is needed (existing catalog resource)

## 2. Gate mark swap

- [x] 2.1 Replace the `clock.arrow.circlepath` image with the template-rendered `BrandMark` at 68pt (`scaledToFit`, `Theme.accentPrimary`, `accessibilityHidden(true)`) in `RootView.restoringSplash`
- [x] 2.2 Apply the identical mark (same asset, tint, frame) in `WelcomeView`; keep the shared-mark comment contract in `RootView`

## 3. Verification

- [x] 3.1 Simulator screenshots: restoring splash and Welcome side by side, light + dark, EN + RU — confirm one continuous mark, 68pt presence, no layout shift vs baseline
- [x] 3.2 Confirm OS launch → splash background seam is unchanged (plain `BackgroundPrimary`, no flash) and Track/History timer glyphs are untouched
- [x] 3.3 Run `swiftlint lint --strict`, warning-clean `xcodebuild` build, and the iOS test suite (`AuthGateTests` restoring-splash cases green) per `docs/ios-test-loop.md`

## 4. Docs

- [x] 4.1 Update `Design/SCREENS/Auth.md` Welcome layout item 2 to the `BrandMark` row and re-check its Implementation checklist
- [x] 4.2 Re-check the relevant `Requirements/FURPS/Sign-up_and_Sign-in.md` rows for conflicts; `docs/project-context.md` needs no architecture update (no new surface)
