## Why

The Lifio beta's app icon looks **pixelized on the public TestFlight listing** (`testflight.apple.com/join/zy7fZuEy`), and **soft even in the TestFlight iOS app**. Investigation (explore session, current tree) traced this to two compounding causes, not a packaging mistake:

1. **Apple's listing pipeline degrades the artwork.** The page serves the icon as a **152×152, quality-80, ~10 KB PNG** (`.../152x152ia-80.png`) displayed at 150–152 CSS px — so every retina screen upscales it ~2× in-browser. Diffed against our local art resized to the same 152px: **mean abs diff 10.5, p95 41**; the white glyph interior is dulled to **~240 instead of 255**; the bar edge smears over ~4px (our master: clean 2px AA). The served file also bakes in rounded corners + transparency.
2. **Our artwork is fragile under that pipeline.** Thin white `^▬` strokes, a faint low-contrast wave texture, and a drop shadow are exactly the high-frequency / low-contrast detail that a 152px + q80 derivative destroys first (waves already render as blotchy noise in the served file). Separately, the shipped 120/180px home-screen slots show **1px hard edge steps** (`108 → 255`, no intermediate pixels) from the original iconkitchen downsample, where the 1024 master has smooth antialiasing — the likely source of the on-device softness.

Slots, sizes, and metadata are all correct (every PNG matches its declared `size × scale`; 1024 alpha fully opaque) — so re-uploading the same binary cannot fix the listing. The artwork itself must be hardened.

## What Changes

- Harden the icon artwork for small-size / low-quality survival: flatten the background (solid color, no fine wave texture), preserve the `^▬` glyph geometry 1:1 (measured stroke 80px/7.8% is already above the legibility floor — no thickening), remove shadow-dependent detail — per HIG icon guidance (see cites).
- Regenerate the authoritative `Design/icon/ios/` slot package from a vector SVG master (rendered 1024 via `rsvg-convert`, slots via Lanczos), preserving antialiased edges at 120/180px; synchronize the verbatim copy into `AppIcon.appiconset`.
- Keep classic `AppIcon.appiconset` packaging (no `.icon`/Icon Composer migration): Apple docs explicitly bless asset catalogs as the ongoing alternative ("verwende weiterhin Asset-Kataloge"), and only the Icon Composer GUI app authors `.icon` files — no CLI path exists for this agent. Dark / clear / tinted appearances ride system auto-generation (which Apple supports for unprovided variants); verify the generated appearances on-simulator instead of hand-rolling them.
- Add observable `app-icon` delta requirements covering listing-derivative survival and small-slot edge quality, with recorded repro evidence and re-verification against the same repro.
- Non-goals: changing the brand mark concept (still `^▬`), alternate/dark/tinted icons, touching SwiftUI in-app branding (`BrandMark` asset), code or build-system changes (`project.yml` untouched), backend/OpenAPI/strings changes.
- Permission gate: regenerating the package commits ~21 binary PNGs — per `AGENTS.md` ("No binaries in git without explicit user permission") implementation MUST obtain the user's explicit permission before committing them.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `app-icon`: ADDED requirements that shipped artwork stays crisp through store-listing derivatives and renders with antialiased edges at small slots; the existing approved-artwork / role-coverage / traceability requirements are unchanged.

## Impact

- Affected files: `Design/icon/ios/` (regenerated), `ios/TimeOfLife/TimeOfLife/Resources/Assets.xcassets/AppIcon.appiconset/` (re-synced copy), `Design/README.md` only if the regeneration flow changes the documented sync rule; no Swift, no plist, no entitlements.
- Verification needs a new beta upload before the listing half of the repro can be re-run (TestFlight reprocesses art per build); the slot half verifies locally pre-upload.
- Research bundle (ctx7, pin "iOS 18 SDK via Xcode 16+"): HIG `/websites/developer_apple_design_human-interface-guidelines` — `app icon design guidelines sizes` + `App Store app icon 1024 marketing artwork requirements`; Apple Developer Documentation `/websites/developer_apple_de` — `configuring app icon set in asset catalog Xcode`. No waivers — UI + Apple-toolchain change.
