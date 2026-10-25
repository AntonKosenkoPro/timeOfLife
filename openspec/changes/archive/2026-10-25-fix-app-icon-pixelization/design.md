## Context

See `proposal.md` for the diagnosis (Apple serves a 152px q80 derivative at 150–152 CSS px; our thin-stroke / textured / shadowed artwork degrades first; 120/180px slots have 1px hard edges) and `specs/app-icon/spec.md` for the observable contract. This is a **pure asset change**: no Swift, no plist, no `project.yml`, no strings, no backend. The repo invariants that constrain it: `Design/icon/ios/` stays the authoritative source package copied verbatim into `AppIcon.appiconset/` (`Design/README.md` sync rule); XcodeGen-managed project; no binaries committed without explicit user permission (`AGENTS.md`).

Cites constraining this design (pin "iOS 18 SDK via Xcode 16+"): HIG `/websites/developer_apple_design_human-interface-guidelines` — `app icon design guidelines sizes` (simplicity; minimal shapes; simple solid/gradient background; "avoid extremely thin line weights and sharp corners, because they tend to lose detail and crispness in smaller icon sizes at lower resolutions"); Apple Developer Documentation `/websites/developer_apple_de` — `configuring app icon set in asset catalog Xcode` (single image per platform that Xcode uses to generate variants, or per-variant images).

## Goals / Non-Goals

**Goals:**
- New 1024 master that survives 152px + q80: flat background, `^▬` glyph geometry preserved 1:1 from measured bitmap outline, no shadow-dependent detail — same brand concept, hardened execution.
- Vector SVG master (`Design/icon/icon-master.svg`, plain text) as the single source: `rsvg-convert` renders the 1024, PIL Lanczos derives all slots. Regeneration is reproducible, no hand-drawn drift.
- Regenerated per-slot package with a high-quality downsample filter so 120/180px edges are antialiased.
- Recorded before/after evidence on the identical repro (served-derivative diff + slot edge profiles + on-device visual).

**Non-Goals:**
- New brand concept, alternate/dark/tinted variants, in-app `BrandMark` changes.
- Switching to Xcode's single-universal-icon derivation (see decision below).
- Any code, config, or contract change.

## Decisions

### Harden the artwork, don't fight Apple's pipeline

Apple's listing markup (152px art at ~152 CSS px, q80) is not ours to change, and every beta goes through the same derivative. The fix is artwork that degrades gracefully: flat background (measured original texture was the mottling source — verified by A/B: flat replica diffs clean while the textured original mottles), glyph geometry preserved 1:1, drop shadow removed. This follows the HIG guidance cited above directly — our waves + shadow are the exact features HIG warns lose crispness at small sizes.

Stroke weight is deliberately NOT thickened: measured perpendicular stroke is 80px (7.8% of 1024 ≈ 12px at listing size), already well above the legibility floor; thickening would drift the brand for unproven gain. Deferred pending verification — if the listing check (3.3) still shows weak glyph presence, thickening is the fallback.

### Pixel-faithful SVG master rendered with pinned tools

The master is a hand-built SVG traced from measured bitmap geometry (apex, knees, spike-foot tips, bar rect verified against row-by-row white-pixel scans), not an auto-trace: background `#0A84FF` (sampled), white hexagon + bar. Rendered with `rsvg-convert`, slots derived with PIL Lanczos. Both are available on the dev machine and scriptable, so any future icon tweak is a text diff + re-render. The SVG itself commits as plain text (no binary-gate issue); only the rendered PNGs need the binary permission.

Alternative considered: keep the artwork and only re-export slots. Rejected — slot re-exports cannot affect the listing derivative, which is generated from the 1024 master by Apple.

### Keep the explicit per-slot package, regenerate with Lanczos (no `.icon` migration)

Regenerate all 21 slots from the new 1024 master with a high-quality filter (Lanczos), then re-sync the verbatim copy into `AppIcon.appiconset/` per the existing `Design/README.md` rule. Explicit slots keep coverage independently verifiable (`size × scale` checks) and preserve the in-force `app-icon` baseline contract unchanged.

Apple's own docs keep asset catalogs as a valid packaging choice alongside Icon Composer files, and `.icon` bundles are authored only through the Icon Composer GUI app — there is no scriptable path to produce or verify one here, and hand-authoring its private format risks unverifiable build behavior. Rejected: migrating to `.icon` in this change.

### Appearances: designed default, system-generated rest, verified on-simulator

HIG asks for dark/tinted variants that feel at home, and supports system auto-generation for unprovided ones. Our flat art (solid bg, single white glyph) is the best-case input for that generation: darkening a flat blue and template-izing a white glyph degrades gracefully, unlike texture/shadow art. Instead of hand-rolling appearance assets the catalog schema cannot express, verification screenshots the system-generated dark / tinted / clear renderings on-simulator (tasks 3.x) — if any looks wrong, designed variants (via the Icon Composer GUI app, human step) become the follow-up.

### Gate binary commits on explicit user permission

Regenerating the package replaces ~21 PNGs. Per `AGENTS.md`, no binaries commit without the user's explicit permission — the implementer MUST ask before `git add`ing them. Repro evidence (downloaded listing art, screenshots) stays in `/tmp`, never in the repo.

## Risks / Trade-offs

- **Listing verification requires a beta upload.** The listing half of the repro can only be re-run after a build with the new icon is processed by TestFlight; slot-level checks and on-device checks gate the upload, not the reverse.
- **On-device "not 100% crispy" may only partially improve.** The TestFlight iOS app list also uses compressed CDN art; if residual softness there comes from Apple's cell rendering rather than our slots, hardening reduces but may not eliminate it. The home-screen icon (our 180px slot, direct render) is the surface this change fully controls.
- **Design taste risk:** flattening removes texture character. Mitigation: keep the Lifio blue + `^▬` concept identical; only stroke weight, background flatness, and shadow change — reviewable in one 1024 file before any slot work.
