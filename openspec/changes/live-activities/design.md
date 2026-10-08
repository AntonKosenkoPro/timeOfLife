## Context

See proposal.md (Why). Current state: the running timer lives only in-app (`TrackState` machine, `TimerService` → `LocalStore.timer_state` singleton in App Group `group.com.antonkosenko.timeoflifeapp`). `timer_state` is already documented as cross-process readable; no extension target exists in `project.yml` (the `LifioControlWidget` target was removed under `bump-ios-deployment-to-18` — its `xcodegen`/regen pitfalls in that archive apply here). Track already reconciles external stops (draft vanishes → leave `.running` on next load). Deployment floor is iOS 18, so no availability guards.

Constraints (from `docs/project-context.md`): `LocalStore` is the single mutation chokepoint; OpenAPI untouched; pre-release — no on-disk migration; `Theme` colors only in app views; strings in both locales + `L10n`; XcodeGen-managed (`project.yml` edit + `xcodegen generate`, never hand-edit `.pbxproj`).

ctx7: `/websites/developer_apple_activitykit` — "Live Activity lifecycle states…", "implement Live Activity ActivityConfiguration…", "open app from Live Activity widgetURL Link tap", "interactive button AppIntent Live Activity end dismissalPolicy". Pin: iOS 18 SDK via Xcode 16+.

## Goals / Non-Goals

Goals: one Widget Extension hosting the timer `ActivityConfiguration`; request/end wired to the existing Start/Stop call sites; Stop intent reusing the `manual` save path; deep link to Track; Saved-then-dismiss ending.
Non-goals (design-level): no `ControlWidget` in this extension; no push tokens; no per-second `update()` loop; no shared-`Theme` refactor beyond what the extension needs to render (see D4); no sync from the extension.

## Decisions

**D1 — Attributes vs ContentState split.** `TimerAttributes` (static: exact text, first-category icon symbol) + `ContentState` (dynamic: `startedAt: Date`). Elapsed renders via `Text(timerInterval:)` so the system ticks with zero updates. Alternative (pushing elapsed strings via `update()` every second) rejected: rate-limited, battery-costly, and the sole source of avoidable `stale` transitions. The compact timer carries an explicit `.frame(width: 52)`: the timer view has no intrinsic size — it fills any proposal (stretching the pill edge-to-edge) and collapses to zero under `fixedSize` (both observed on-device; same root cause as Mobileraker #273). Twin-`overlay` hugging was tried per device feedback and reverted: it does not constrain in the compact slot (pill went wide again), while the frame era was explicitly confirmed good. 52pt fits H:MM:SS in the ~52–62pt slot; monospaced digits keep shorter values stable. The expanded timer border instead hugs dynamically: the live view has no intrinsic size, so a hidden static twin in the same format (`TimerClock.liveStyle`) sizes the capsule via `overlay` (overlay content takes no part in layout — a `ZStack` sizes to every child including the stretchy live view and goes full-width again) — no fixed points (Dynamic-Type-safe), growing with the digits. The twin freezes at render time, so a phase crossing without a re-render keeps the previous width until the next render (text may spill past the border, never clipped).

**D2 — Singleton guard.** Before `request()`, query existing activities for our attributes type; reuse or `end()` the stale one first. Alternative (request blindly) rejected: duplicate Islands after crash-relaunch (draft survives crashes by design).

**D3 — Stop intent writes through `LocalStore`.** The intent resolves the active account file (same resolver the app uses) and calls the existing stop transaction (`createEntry` + `clearTimerDraft` + outbox row); `source='manual'`. Alternative (new `liveactivity` source) rejected by user decision — no provenance, History shows no "via" label. Alternative (intent writes GRDB directly) rejected: violates the single-chokepoint invariant.

**D8 — The intent never ends the activity; the app reaps orphans.** The shared attributes file compiles into two modules (`TimeOfLife` + `LifioLiveActivities`), which ActivityKit treats as two distinct types: the extension's `Activity<Attributes>.activities` is always empty (observed on-device — "Activities changed: []" with a live island — while `mangledTypeName` logging confirms module-qualified matching), so ending from the intent is a guaranteed no-op. Instead the intent posts a Darwin signal (`LiveActivitySignal`, no entitlements needed) carrying the true duration, and the app ends the orphan: instantly via the Darwin handler while live (Saved card + timed dismissal), silently-immediate on foreground/load catch-up (no invented duration), and Track/compact reload through an in-process note so no stale running UI survives. Only `.active` activities are touched — an `.ended` Saved card keeps its own dismissal.

**D4 — Extension theming.** As built: no custom palette at all — system default activity background, semantic red/white Stop control mirroring `CompactTimer`'s danger circle. The shared `Localizable.strings` ship in the extension bundle (single source); data-only `Shared/` types (`TimerActivityAttributes`, `TimerClock`, `LiveActivityStrings`) compile into both targets. App-only modules (`Theme`, `L10n`) stay out. The `bump-ios-deployment-to-18` archive's target-removal notes cover the `xcodegen` side (capabilities block, `postGenCommand` normalization — extended to multi-target in `normalize-system-capabilities.py`).

**D5 — Navigation.** `widgetURL(lifio://track)` on compact/minimal/banner; `Link` + `widgetURL` in expanded (Go row). `RootView` handles the URL by selecting Track. Default system open (no URL) rejected: must land on Track, not relaunch state.

**D6 — Dismissal.** `end(finalContent, .after(now + T))`, T tuned in testing (~6s starting point). `.immediate` rejected (no Saved moment); `.default` rejected (4h linger). Island collapses at `end()`; banner shows `✓ Saved <duration>` until T.

**D7 — Dimmed rendering.** Stop controls render only in interactive contexts (`fullColor` rendering mode AND full luminance). Always-On is detected via `isLuminanceReduced` — the documented signal (`/websites/developer_apple_activitykit` — "isLuminanceReduced Always On dimmed Live Activity"; `widgetRenderingMode` stays `fullColor` under dimming). Banner content joins the accent group when dimmed (`widgetAccentable`) AND carries explicit saturated orange tint (Apple Timer's own face): either mechanism alone left the banner blank across successive device builds, so both ship at once — whichever the AoD renderer honors, content stays visible. The banner elapsed keeps the coarse masked reading (`58:--` via `TimerClock.maskedCoarse`) under dimming, set big and bold — small dimmed type photographs as blur (device finding against Apple's own large readout).

**AoD probe (WIP, device-verdict pending):** the banner is stripped to plain static text — always-coarse `BannerElapsed` (no ticking view, no luminance gate), no `AodTint`/`AodAccentable` wrappers, SHA fingerprint line removed — to isolate whether the live timer view or accent-group membership blanks the dimmed face. If the probe reads on AoD, reintroduce styling stepwise (gated coarse → tint → accent) to find the breaking element. If the probe still blurs, the cause is outside content (layout/budget) — escalate to the Apple doc fallback list in the audit. The extension target keeps one `sources:` list only (a second key replaces the first — this shipped an appex with no executable), and shared strings ride as explicit `buildPhase: resources` file entries (`resources:` globs are silently dropped for paths the app target already owns — this rendered raw keys on every face).

## Risks / Trade-offs

- [Extension reads a file mid-migration] → Extension opens read-only and fails to the graceful face; all writes stay app-side. Mitigation: never open read-write from the extension.
- [Stop tapped during an in-flight app Stop] → Second stop finds no draft; intent treats missing draft as success (idempotent, mirrors 404-as-success in sync).
- [Two activities squeeze (music + timer)] → Minimal face must survive at icon size; covered by spec scenario, verify with a music session in testing.
- [Widget-SwiftUI subset] → No `TimelineView`, limited modifiers; keep faces to `Text`/`Image`/`Button`/`Link` + `DynamicIslandExpandedRegion`.
- [`xcodegen` regen wipes capabilities] → Declare App Group + deep-link scheme in `project.yml`, run `generate`, verify attendant `SystemCapabilities` (same failure mode as the SIWA incident).

## Migration Plan

No migration: additive target + additive `timer_state` readers; existing drafts unaffected. Rollback = remove extension target (single `project.yml` revert + delete sources). No backend deploy.

## Open Questions

- **Q1 (deferrable, decided in testing): dismissal seconds T.** Starting point ~6s; tune against real Island/banner behavior. Changing T alters no spec requirement (spec says "tuned delay") and no task breakdown.
