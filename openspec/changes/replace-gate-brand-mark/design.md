## Context

See `proposal.md` — Why for motivation. Current state: `RootView.restoringSplash` and `WelcomeView` each render `Image(systemName: "clock.arrow.circlepath")` at 48pt light in `Theme.accentPrimary`, with an "Lifio" title below (the shared-mark contract lives only as a code comment in `RootView`). The OS launch screen (`UILaunchScreen`) is a plain `BackgroundPrimary` color with no image. Constraints: Theme-only colors, no new strings (U4), XcodeGen-managed project, asset catalog owned by the app target, in-repo art must be traceable to its source.

No external-dependency behavior is involved (SwiftUI `Image` + asset catalog only — established repo-internal practice), so no ctx7 fetch applies.

## Goals / Non-Goals

**Goals:**

- Both gate surfaces render the real `^▬` glyph at one shared size/tint, preserving today's layout rhythm and background-seam continuity.
- The new asset is traceable: source file + trim geometry recorded here, PNGs committed to the catalog.

**Non-Goals:**

- No OS-launch-screen image (keeps `project.yml`/plists untouched — no regen, no hand-mirroring risk).
- No structural refactor of the two screens (no shared view extraction; duplication stays, comment stays).
- No vector redraw of the mark in this change (raster trimmed from IconKitchen; see Risks).

## Decisions

### 1. Asset source: IconKitchen monochrome, trimmed — over foreground / full tile / vector redraw

The `xxxhdpi` `ic_launcher_monochrome.png` (black `^▬` on transparency, 432²) is the semantic single-color source; its mask is pixel-identical to the white foreground's (verified: both ink bbox x 158–273, y 155–273), so either re-tints the same — monochrome is chosen as the honest "recolor me" layer. Full-tile art (`web/icon-512.png`) is rejected (glyph baked onto blue; wrong voice for the gate). Vector redraw (two rounded rects as PDF) is the crispest option but needs designer time and is deferred — the mark is chunky geometry that survives a ~1.5× upscale acceptably (see Risks).

### 2. Trim the 97%-transparent canvas before cataloguing — never raw drop-in

Raw PNGs carry adaptive-icon safe-zone padding (ink is 116×119 of 432², ~27%). Trim to the ink bbox plus ~12% breathing room (≈144×147 master), then scale to 1x/2x/3x for a `BrandMark.imageset` inside the existing `Assets.xcassets` (no `project.yml` change — the catalog is already an app-target resource; folder contents are picked up without regen). Source recorded: `/Users/antonkosenko/Downloads/IconKitchen-Output/android/res/mipmap-xxxhdpi/ic_launcher_monochrome.png`.

### 3. Render as template in `Theme.accentPrimary` at 68pt — over original-color / new token / 48pt parity

Template + `accentPrimary` (`#0A84FF`, identical light/dark) keeps today's glyph voice with one tint both modes — no new `Theme` token, no imageset appearances. 68pt frame height (`scaledToFit`, aspect ≈116:119) sits mid-ladder between parity (64) and statement (72): reads as "the new logo" without shifting the splash↔Welcome centroid or the `VStack(spacing: 16)` rhythm. Both call sites use the same frame value; `accessibilityHidden(true)` stays.

### 4. In-place swap in both views — over extracting a shared `BrandHeader`

Two one-line image swaps plus identical frames. A shared component would be cleaner long-term but expands scope (new file, `COMPONENTS.md` entry, previews) for a mark change; the existing comment contract plus a side-by-side screenshot verification task holds parity for now.

## Risks / Trade-offs

- [Risk] Trimmed master (~147px tall) upscales ~1.5× at 68pt@3x (204px) → slight softness under close inspection → Mitigation: accept (hard-edged geometry degrades gracefully); screenshot verification task judges real-device rendering; vector redraw is the documented follow-up, not this change.
- [Risk] Raw-padding trap (glyph renders ~13pt if untrimmed PNG is catalogued) → Mitigation: trim is an explicit task with bbox numbers above; verification task compares rendered glyph against the 68pt expectation.
- [Risk] Splash↔Welcome drift (two literals, no shared view) → Mitigation: same frame constant in both edits + side-by-side screenshot task before merge.
- [Risk] Dark-mode wash (blue on `#0B0B0F`) → Mitigation: none needed — `accentPrimary` already renders glyphs on both backgrounds today (current mark proves the contrast); screenshots cover both modes.

## Migration Plan

None — no data, no API, no flags. Visual-only change behind the existing gate; rollback is a revert. Release notes: none required (pre-release, cosmetic).

## Open Questions

None — source, voice, size, and scope were all settled in explore; the 64–72 range is pinned to 68 here, adjustable at implementation with screenshot evidence without changing specs.
