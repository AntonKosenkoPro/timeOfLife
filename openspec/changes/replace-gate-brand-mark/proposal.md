## Why

The auth gate (restoring splash + Welcome screen) still renders a generic SF Symbol (`clock.arrow.circlepath`) as its brand mark, while the shipped product identity is the Lifio `^▬` glyph (blue tile icon, `Design/icon/`). Replacing the placeholder mark with the real product glyph makes the gate recognizable as Lifio from the first frame, at zero cost to the current seamless background continuity.

## What Changes

- The restoring splash (`RootView.restoringSplash`) renders the Lifio product glyph instead of `clock.arrow.circlepath`.
- The Welcome screen (`WelcomeView`) renders the same Lifio product glyph instead of `clock.arrow.circlepath`.
- The glyph is single-color (template render, `Theme.accentPrimary`), enlarged vs today's 48pt mark (64–72pt target), identical on both surfaces to preserve the splash↔Welcome shared-mark contract.
- A new `BrandMark` image set in `Assets.xcassets`, trimmed from the IconKitchen monochrome source (`ic_launcher_monochrome.png`: black `^▬` on transparency), ships with the app target.
- `Design/SCREENS/Auth.md` documents the new brand-mark row for the Welcome screen (layout item 2) and its checklist keeps passing.

Explicit non-goals (unchanged by this change):

- The OS launch screen (`UILaunchScreen`: plain `BackgroundPrimary` color, no image) is untouched — background-seam continuity is preserved as-is; no `project.yml` / plist edits.
- Track/History/timer glyphs (`TrackContent` name rows, History tab icon, `EmptyState`, compact timer) keep their SF Symbols.
- No new user-facing strings (U4 unaffected), no new color tokens (tint is the existing `Theme.accentPrimary`), no backend/API/OpenAPI changes, no Light/Dark variants (one tint both modes).

## Capabilities

### New Capabilities

(none — this change restates existing surfaces with the real brand mark; no new capability.)

### Modified Capabilities

- `app-identity`: the Welcome-screen brand presentation gains a mark requirement — the product glyph (`BrandMark` asset, single-color template) renders above the "Lifio" title in place of the generic timer symbol.
- `app-shell`: the restoring splash's "app identity" is pinned to the same product glyph at the same size, so the restore→auth transition keeps one continuous mark.

## Impact

- iOS: `Features/Auth/Views/RootView.swift` (restoring splash mark), `Features/Auth/Views/WelcomeView.swift` (Welcome mark); optionally one shared brand-header view if the implementer chooses to structuralize the shared-mark contract (currently a code comment + duplicated layout).
- Assets: new `BrandMark.imageset` in `TimeOfLife/Resources/Assets.xcassets` (trimmed + scaled from the IconKitchen monochrome PNG; app target resources only — no appex, no `project.yml` changes).
- Docs: `Design/SCREENS/Auth.md` (Welcome layout item + checklist); no `docs/project-context.md` architecture change (no new surface, no contract change beyond the mark).
- Tests: existing `AuthGateTests` restoring-splash cases keep passing (accessibility identifiers unchanged); no new test target work expected beyond a mark-presence assertion if the implementer adds one.
- Source art lives outside the repo (`/Users/antonkosenko/Downloads/IconKitchen-Output`); the trimmed/scaled PNGs committed to the catalog become the in-repo source of truth, with the IconKitchen path recorded in `design.md`.
