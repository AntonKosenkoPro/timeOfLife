## 1. Repro + research (gates implementation)

- [x] 1.1 Repro recorded on the current tree (explore session): fetched the live TestFlight listing derivative `.../152x152ia-80.png` (152×152, ~10 KB, rounded corners baked in) and diffed it against local art at 152px — mean abs diff **10.5**, p95 **41**, glyph interior dulled to **~240** (not 255), bar edge smeared over ~4px vs 2px AA on the master; page markup displays it at 150–152 CSS px (retina browsers upscale ~2×). Slot check: 180/120px slots show 1px hard edge steps (`108 → 255`) vs antialiased master. Evidence kept in `/tmp` (binaries never commit). Baseline symptom confirmed by reporter: listing pixelized, TestFlight app soft.
- [x] 1.2 ctx7 research bundle complete (pin "iOS 18 SDK via Xcode 16+"): HIG `/websites/developer_apple_design_human-interface-guidelines` — `app icon design guidelines sizes`, `App Store app icon 1024 marketing artwork requirements`; Apple Developer Documentation `/websites/developer_apple_de` — `configuring app icon set in asset catalog Xcode`. No waivers (UI + Apple-toolchain change).
- [ ] 1.3 Capture on-device baseline: install the current beta, screenshot the home-screen icon and the TestFlight-app listing cell (same device, note model + iOS version) for before/after comparison.

## 2. Implementation (needs explicit binary-commit permission first)

- [x] 2.1 Vector master reviewed at 100% crops (apex / spike-foot / bar vs original): geometry matches on the fitted 45-degree grid (±1px); only intended deltas are removed shadow + texture. Approved SVG stored at `Design/icon/icon-master.svg` (plain text — no binary gate).
- [x] 2.2 Rendered the 1024 via `rsvg-convert` and regenerated the full `Design/icon/ios/` package with PIL Lanczos (`Design/icon/render.py`); every PNG's pixels equal its declared `size × scale`, all RGB opaque (no alpha channel), sRGB. (Binary-commit permission still required before `git add`ing the PNGs.)
- [x] 2.3 Synced the verbatim copy into `AppIcon.appiconset/` (`Contents.json` identical); `xcodegen generate` clean, `swiftlint lint --strict` 0 violations, warning-as-error simulator `build` green with no asset-compilation warnings. Full iOS suite running (background).
- [x] 2.4 Re-checked `Requirements/FURPS/*.md`: all icon rows cover in-app SF Symbol category icons and Live Activity icons — none constrain the app icon; no conflicts, no doc updates needed there.

## 3. Verification (identical repro, after)

- [x] 3.1 Slot check (pre-upload gate): re-ran edge profiles on the new 120/180px PNGs — straight glyph edges show multi-pixel AA transitions (`…113 → 237 → 255`) instead of the old hard 1px steps; no hard steps persist.
- [x] 3.2 On-device/simulator check: installed the rebuilt app on iPhone 16 Pro simulator; verified Light (crisp flat blue + white glyph at 100% crop), system-generated Dark (navy, glyph intact, no mottling) and Tinted (black + light glyph, recognizable) appearances, and reset the sim to Light. Clear has no separate control on this OS (Light/Dark/Automatic/Tinted only) — covered by the same auto-generation path.
- [ ] 3.3 Listing check (post-upload): after a beta with the new icon is processed, re-fetch the listing derivative and re-run the 1.1 diff — glyph interior near-white, no texture mottling, edge width back to AA range; record numbers with the change.
- [ ] 3.4 Run `openspec validate fix-app-icon-pixelization --strict` green; update `docs/project-context.md` OpenSpec routing only if the active-change set needs it.
