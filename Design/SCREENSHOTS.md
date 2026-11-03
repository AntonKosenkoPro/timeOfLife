# App Store Screenshots — Capture Storyboard

> Status: **English pilot APPROVED (task 5.4, 2026-10-30).** The 7-frame
> iOS 27 set `runs/pilot27-r2` (deck `en-austin-1`, treatment `light-v1`,
> 1320×2868, status `complete`) is owner-approved — Jan-1 Lock-Screen date
> accepted as a disclosed artifact, device-local times accepted,
> contact-sheet template approved. iPhone 6.9-inch expansion captured (4
> non-en locales × 2 runs × 7 frames); 6.5-inch + iPad sets captured (5
> frames each, Island states N/A by design — recorded, never fabricated).
> Final fifteen-set acceptance (6.6) still pending — captured ≠ approved.
> Montage deferred (built, retained externally, NOT approved). Nothing here
> is a new production feature or a change to shipped UI.

## Story order (seven frames, native product views only)

Capture real views with real domain reads — never mock screens or image edits:

1. **Track running** — running timer with selected categories (`SCREENS/TimeTracking.md`).
2. **Insights** — default week, By-category lens (`SCREENS/Insights.md`).
3. **History** — TOP viewport: Today/Yesterday + day totals, newest first (`SCREENS/History.md`).
4. **Add entry** — genuine Log Time sheet with all five cards (Name, Start, End, Categories, Notes) + sample content incl. a visible notes value.
5. **Live Activity — Lock Screen banner** — genuine running activity (see below).
6. **Live Activity — Dynamic Island compact** — required on the Island class (see below).
7. **Live Activity — Dynamic Island expanded** — touch-and-hold, required on the Island class (see below).

Prior 5-frame drafts (name-picker frame, History notes-viewport recapture)
are SUPERSEDED per the 2026-10-30 owner correction: the picker frame is
REMOVED, replaced by Add-entry; History MUST show the top viewport.

## English pilot defaults (approved inputs — approval tied to hashes)

- Reference: Tuesday 2026-10-20, 09:41 local · app-owned elapsed 12:34 (754 s).
- Light appearance · standard Large Dynamic Type · en / US / America/Chicago.
- iOS 27 runtime · iPhone 1320 × 2868 portrait · clean 9:41 status bar, full battery, stable network.
- Input pin: `scripts/screenshots/pilot_manifest.json`; totals cross-pinned in
  `scripts/screenshots/expected_totals.json` (FINAL handoff 2026-10-30:
  runner 149, Debug 901, Screenshot 914 — all green). Fixture: 21-day /
  55-entry English Austin deck (`en-austin-1`; Food pin `shot-cat-food 41400`
  live; locale-native week rule — ru/Moscow 12300 s vs 23100 s elsewhere).
- Two consecutive full pilot runs completed (`runs/pilot27-r1` +
  `runs/pilot27-r2`); approval is tied to the `pilot27-r2` frame hashes
  recorded in task 5.4 / `approval-pilot27-r2.json`.

## Capture matrix (expansion — English approved 5.4; 6.6 acceptance pending)

Five locales (en, ru, zh-Hans, es-419, pt-BR) × three sizes:

- 6.9-inch iPhone 1320 × 2868 — 7 frames (full story incl. all 3 LA states).
- 6.5-inch iPhone 1242 × 2688 — 5 frames (Island compact/expanded N/A by
  design, Lock banner required + present).
- 13-inch iPad 2064 × 2752 — 5 frames: the actual iPad layout at native
  dimensions — never stretched iPhone frames — with per-run Island-N/A
  home probes; Lock banner required + present. Real-date iPad status bar
  accepted (no 9:41 override on iPad); centered-column layout accepted.

Actual required raws per round: 5×7 + 10×5 = 85 (Island N/A is recorded,
never fabricated); ×2 runs = 170 PNGs. es-419 app captures map to the
Spanish (Mexico) Store listing. Every set: two successful runs, numeric (not
pixel) validation of dynamic timers, locale-by-locale clipping review
(Spanish/Portuguese first — DONE 2026-10-30: no iPhone clipping in any
locale/size; iPad Add-entry Notes peek/hidden split is an owner call at 6.6).

## Live Activity frames (genuine system behavior, 3 states)

- Real foreground request, real start anchor, recorded timestamps; elapsed
  validated within ±2 s. System-owned dates/effects are disclosed, never retouched.
- Lock Screen banner required on every size. Island compact + expanded are
  required on the Dynamic-Island 6.9-inch class; on non-Island targets they
  are N/A (recorded with probes, never fabricated).
- The "Saturday, 1 January" Lock-Screen date is an accepted disclosed
  artifact (9:41 time-only-override side effect; ISO probe dead end).
  Device-local times on home-screen clocks are accepted.
- If a required presentation is unavailable, the frame stays blocked and the
  set incomplete; no substitute counts.

## Landing montage (asset only — DEFERRED)

- Owner-deferred 2026-10-30: a built asset is retained externally
  (`montage/landing-en-1920x1080.png` + preview JPG, Pillow 13.0.0 recipe
  from approved `runs/pilot27-r2` Track/Insights/History), but it is NOT
  approved and NOT integrated. No `web/` changes. All 7.x stays open/deferred.

## Review gates (5.4 APPROVED English; 6.6 pending)

English pilot raw PNGs + text manifest are retained at the agreed external
root (`/Users/antonkosenko/Pictures/LifioScreenshots/app-store-screenshot-pilot`),
hashes verified, owner explicitly approved content, composition, and
treatment tied to the `pilot27-r2` hashes. Changed frames require renewed
approval. The final fifteen-set manifest + review reports still need owner
acceptance (6.6) — captured never implies approved. Tests passing never
implies approval.

## Implementation checklist (see tasks.md for the authoritative per-task state)

- [x] Screenshot configuration/scheme + simulator/physical-device gates (2.2; 2.1 explicit archive guard still open)
- [x] Awaited capture composition + isolation from production state (2.3–2.5)
- [x] Preparation pipeline using LocalStore APIs (3.2); coherent app time (3.3); fixture definition (3.1)
- [ ] Frame scenarios for History-top + Add-entry (3.4 — prior notes-viewport/picker drafts superseded)
- [x] Approval-metadata code/tests (4.5); runner base proven through pilot27 + expansion captures
- [ ] 7-frame/iOS 27 runner extension + evidence sheets (4.1–4.4)
- [x] Pre-capture verification + **5.4 owner approval** of the English 7-frame iOS 27 set
- [x] iPad capture (6.4, completeness only) + clipping review (6.5); 6.9-inch iPhone sets complete + 6.5-inch captured (6.3 partial — manifests/clearance pending)
- [ ] Final fifteen-set acceptance (6.6); montage deferred (7.x); final handoff (8.1/8.3/8.4)

Done so far (code/test/evidence level): research bundle (1.1), rebase + FURPS read
(1.2), retrospective seam evidence + owner-acknowledged deviation recorded
(1.3 — future repro rule unchanged), input/totals pins (1.4), Screenshot
config audit + composition + Release-negative + isolation code/tests
(2.2–2.5), fixture definition (3.1), preparation pipeline + clock forwarding
code/tests (3.2–3.3), approval-metadata code/tests (4.5), pre-capture
verification builds/lint/tests (5.1), English 7-frame pilot27 runs + owner
approval (5.2–5.4 — APPROVED, see above), iPhone/iPad expansion captures +
clipping review (6.3 partial, 6.4/6.5 DONE — capture/review only, not
acceptance). Open: explicit archive guard (2.1), frame scenarios (3.4),
runner/evidence extension (4.1–4.4), final acceptance (6.6), montage
(deferred 7.x), final handoff (8.1/8.3/8.4).

## Pointers

- Operator runbook: `docs/screenshot-capture.md`.
- Change contract: `openspec/changes/app-store-screenshot-pilot/` (proposal, design, tasks, specs, research).
- Runner evidence: `scripts/screenshots/evidence-runner.md`.
- Review rules: App Store 2.3.3 (app in use) / 2.3.9 (fictional account info); binaries never in git.
- New app-visible copy still needs all five locales + L10n (U4) — this storyboard adds no app strings.
