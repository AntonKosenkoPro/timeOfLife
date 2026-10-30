# App Store Screenshots — Capture Storyboard

> Status: **ACTIVE change, CAPTURED DRAFT under owner review.** English iPhone
> pilot captured in two full runs on DC79 (raw PNGs + manifests in the agreed
> external root); History notes-viewport frames corrected 2026-10-30 (Deep-work
> glyph visible, day totals present); Lock-Screen Jan-1 is a disclosed
> toolchain dead end. Nothing here is approved — 5.4 gates expansion/montage —
> and nothing here is a new production feature or a change to shipped UI.

## Story order (five frames, native product views only)

Capture real views with real domain reads — never mock screens or image edits:

1. **Track running** — running timer with selected categories (`SCREENS/TimeTracking.md`).
2. **Insights** — default week, By-category lens (`SCREENS/Insights.md`).
3. **History** — day-grouped list with day totals + one visible notes glyph (`SCREENS/History.md`).
4. **Name picker / quick reuse** — idle scenario with normal localized software keyboard (`SCREENS/NamePicker.md`).
5. **Live Activity** — genuine running activity (see below).

## English pilot defaults (pinned inputs, not an approval)

- Reference: Tuesday 2026-10-20, 09:41 local · app-owned elapsed 12:34 (754 s).
- Light appearance · standard Large Dynamic Type · en / US / America/Chicago.
- iPhone 1320 × 2868 portrait · clean 9:41 status bar, full battery, stable network.
- Input pin: `scripts/screenshots/pilot_manifest.json`; totals cross-pinned in
  `scripts/screenshots/expected_totals.json` (runner 131/131 tests green;
  runtime proof still pending). Fixture: 21-day / ~55-entry English Austin deck.
- Two consecutive full pilot runs required before review.

## Capture matrix (after pilot approval only)

Five locales (en, ru, zh-Hans, es-419, pt-BR) × three portrait sizes
(iPhone 1320 × 2868, iPhone 1242 × 2688, 13-inch iPad 2064 × 2752) = fifteen
sets, five frames each. iPad sets show the actual iPad layout at native
dimensions — never stretched iPhone frames. es-419 app captures map to the
Spanish (Mexico) Store listing. Every set: two successful runs, numeric (not
pixel) validation of dynamic timers, locale-by-locale clipping review
(Spanish/Portuguese first).

## Live Activity frame (genuine system behavior)

- Real foreground request, real start anchor, recorded timestamps; elapsed
  validated within ±2 s. System-owned dates/effects are disclosed, never retouched.
- Required presentation is the actual Lock Screen on every device. An expanded
  Island is an optional iPhone-only extra after a real capability check —
  **never fabricate an Island on iPad or the non-Island 6.5-inch phone.**
- If the presentation is unavailable, the frame stays blocked and the set
  incomplete; no substitute counts.

## Landing montage (asset only, after pilot approval)

- English only, from approved pilot frames (Track → Insights → History story).
- Proposed: 1920 × 1080 light landscape, uniform scaling, preserved aspect
  ratios, no invented UI or headline copy. Composition lives in a text recipe;
  montage approval is separate from pilot approval. No `web/` changes.

## Pilot review gate (task 5.4 STOP)

Pilot raw PNGs + text manifest go to the agreed external root
(`/Users/antonkosenko/Pictures/LifioScreenshots/app-store-screenshot-pilot`),
hashes verified, then the owner explicitly approves content, composition, and
treatment tied to those hashes. Changed frames require renewed approval.
No section-6/7 work before this gate. Tests passing never implies approval.

## Implementation checklist (all capture items currently UNCHECKED)

- [ ] Screenshot configuration/scheme + simulator/physical-device gates (2.1, 2.2)
- [ ] Awaited capture composition + isolation from production state (2.3–2.5)
- [ ] Preparation pipeline using LocalStore APIs (3.2); coherent app time (3.3); frame scenarios (3.4)
- [ ] Runner verbs with real-device proof (4.1–4.4); teardown to full success (4.2)
- [ ] Debug/Release/Screenshot verification + two pilot runs + frame inspection (5.1–5.3)
- [ ] **5.4 owner approval** — the only gate that unlocks expansion and montage
- [ ] Localized decks, full matrix, clipping review (6.1–6.6); montage (7.1–7.3); final verification/handoff (8.1–8.4)

Done so far (docs/test level only): research bundle (1.1), rebase + FURPS read
(1.2), retrospective seam evidence + owner-acknowledged deviation recorded
(1.3 — future repro rule unchanged), input/totals pins (1.4), Screenshot
config audit + composition + Release-negative + isolation code/tests
(2.2–2.5), fixture definition (3.1), preparation pipeline + clock forwarding
code/tests (3.2–3.3), approval-metadata code/tests (4.5), pre-capture
verification builds/lint/tests (5.1), runtime workflow + evidence + two pilot
runs (4.1–4.4, 5.2 — CAPTURED DRAFT, not approved). History-with-notes frame
(3.4) DONE 2026-10-30 — reusable `.argent/flows/history-notes-viewport.yaml`
scenario + r1/r2 recapture at the notes viewport (Deep-work glyph + day
totals, Today labels out of frame, no fixture change). Open: explicit archive
guard (2.1), pilot inspection + approval (5.3/5.4 — corrected History frames
for owner review; Jan-1 ISO probe dead end, disclosed; variance clearing,
globe call pending), expansion, montage, final handoff.

## Pointers

- Operator runbook: `docs/screenshot-capture.md` (draft).
- Change contract: `openspec/changes/app-store-screenshot-pilot/` (proposal, design, tasks, specs, research).
- Runner evidence: `scripts/screenshots/evidence-runner.md`.
- Review rules: App Store 2.3.3 (app in use) / 2.3.9 (fictional account info); binaries never in git.
- New app-visible copy still needs all five locales + L10n (U4) — this storyboard adds no app strings.
