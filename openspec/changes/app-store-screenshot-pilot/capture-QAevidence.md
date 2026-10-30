# Capture QA evidence — English iPhone pilot (tasks 5.2/5.3)

QA worker record, 2026-10-30. Two consecutive full pilot runs on the
capture-only simulator. This file reports CAPTURED and REVIEWED state only.
It is not owner approval: task 5.4 still requires explicit owner approval of
content, composition, and treatment before any section 6/7 work.

## Provenance (identical for both runs)

- Device: `DC79DF29-708B-4928-91A9-8CD5B6352671` ("SHOT Pilot Capture
  iPhone16ProMax", iPhone 16 Pro Max, iOS 18.6), native geometry 1320x2868.
  Fresh-created for capture; only the screenshots BID ever installed.
- App: `com.antonkosenko.timeoflifeapp.screenshots` (Screenshot config),
  Mach-O sha256 `47eda86e3f85354b1134c0d8f3f73eecfc3ae9ad75aeb512fc5adbecae55a252`
  (rehashed at handoff; unchanged).
- Repo base `c3e5911`, dirty=true (HEAD not implied as exact build source).
- Xcode 27.1 (27A9275). Fixture `en-austin-1`: 55 entries, pinned totals
  all=198600 / today=4500 / week=23100 + category/text maps
  (`expected_totals.json`).
- The E915 test device and its normal-BID "Reading" Live Activity were never
  touched; shared C18365F5 never targeted. No xcodebuild run by QA.
- Retained root: `/Users/antonkosenko/Pictures/LifioScreenshots/app-store-screenshot-pilot`
  (`runs/pilot-r1`, `runs/pilot-r2`, `contact-pilot-r1.png`,
  `contact-pilot-r2.png`). No Binaries in git.

## Run results

`finalize-run` status: **complete**, pending_evidence [] for both runs.
All 10 per-frame teardowns status **complete** (app ack `cleaned`,
`removed_session: true`, chrome restored, app terminated). r1 LA teardown
ended activity `9891837C-D26E-4B6B-8F0A-78AC38923337`; r2 LA teardown ended
activity `55341AC1-D2D6-4397-B8E5-5B02FA157C91` (ids from live state).
`finalize-two-runs`: semantic equality holds (no errors); status
**needs-inspection** with unreviewed_variance [history, live-activity]
(owner clears per-frame with reviewer+date; never auto-passed).

## Per-frame PNGs (all native 1320x2868)

| frame | pilot-r1 sha256 | pilot-r2 sha256 | cross-run |
|---|---|---|---|
| track-running | `1dcacbe0…cb6b21d5` | identical | byte-identical |
| insights | `992ae012…79e0a9a8` | identical | byte-identical |
| history | `b4cc904f…2426df` | `d2da6b4c…29af0e3` | pixels differ* |
| name-picker | `8945cfd7…4e299d1da` | identical | byte-identical |
| live-activity | `8296fc8e…2a654216` | `09b4bbe9…6590957` | dynamic timer (expected) |

(Full hashes in each `runs/<run>/run-manifest.json`.)
\* history: recaptured 12:16 to the Oct 14–11 viewport (Deep work 2h +
notes glyph visible Oct 12, read from both renders); true raw-pixel diff
on correctly decoded pixels = 1128654 bytes (420449 px of 3.8M, 11.11%)
in rows 0-2408, full width — a scrolled-viewport difference, not the
superseded island shimmer. Residual island presence differs too: r1 shows
no black pill at y≈70 (light ~247), r2 shows the black pill (0,0,0).
track/insights/picker stay byte-identical across runs. Documented for
human review, not cleared. (Superseded 11:53 note: the earlier 118524-byte
/ 0.78% island-edge finding described the pre-12:16 frames
`f2d76f4f…` / `961f7a49…` and no longer applies; do not quote it.)

## Clock / keyboard observations (read from actual renders, never computed)

- App-clock frames: Track 12:34 + Started 9:28 AM; History Oct 14/13/12/11
  day totals with the Deep work notes glyph visible Oct 12 (both runs,
  read from renders); Insights default week. Status bar 9:41
  override rendered on all app frames.
- name-picker: first export showed the first-run slide-to-type tutorial
  overlay (real OS behavior, keys present underneath in AX). One genuine
  Continue tap dismissed it to the real docked QWERTY keyboard; capture
  re-exported (old export superseded, record rebound). r2 showed the genuine
  keyboard directly (dismissal persisted). Inspection: keyboard_visible true,
  docked, language en-US (basis: QWERTY letters + English predictions
  run/running/runs), SHA-bound to the capture file; `verify-picker` passes
  both runs. Evidence artifacts: `runs/<run>/evidence/name-picker.tree.txt`
  (+ `.inspection.json`).
- live-activity (genuine Lock Screen, real system timer):
  - r1: started `2026-10-30T04:29:01-05:00`, captured
    `2026-10-30T11:42:48+02:00`, observed 826 s from PNG (13:46), wall 827 s,
    |diff| 1 s. `verify-la` passes.
  - r2: started `2026-10-30T04:31:43-05:00`, captured
    `2026-10-30T11:46:13+02:00`, observed 869 s from PNG (14:29), wall 870 s,
    |diff| 1 s. `verify-la` passes.
  - captured_at timestamps were recorded immediately after the `simctl io
    screenshot` return in the same shell invocation (within ~1 s of pixel
    capture), timezone-aware, never assumed UTC.
  - r1 showed a compact "Allow Live Activities from Lifio?" banner, dismissed
    with one genuine Allow tap at tree-derived coordinates. r2 showed an
    expanded "Do you want to continue to allow Live Activities from Lifio?"
    card; three taps estimated from downscaled images missed (buttons sit at
    y≈0.805-0.851, estimates were ~0.22 screen-heights high); the exact
    tree-derived point (0.7235, 0.828) granted Always Allow. Lifio Settings
    already showed the Live Activities toggle ON throughout. No Don't Allow
    was ever tapped; the live timer never stopped.
  - Lock-Screen clock/date render as "Saturday, 1 January / 09:41": the 09:41
    is the mandated status_bar override working on the lock clock; the Jan-1
    date is its side effect (real device date Fri 30 Oct, proven by AX tree).
    Disclosed, not retouched; owner decides at 5.4.

## Visible issues for 5.3/5.4 review (not edited, not hidden)

1. Lock-Screen date "Saturday, 1 January" (override side effect; see above).
2. Picker globe key: second installed keyboard is Russian ("Next keyboard"
   value `Русская` in AX; globe icon visible in frame). Active layout is
   English; owner decides whether to keep or remove the Russian keyboard
   (recapture is cheap; QA did not alter device keyboards).
3. history cross-run viewport + island-presence variance (above); track/insights/picker are
   byte-stable across runs.
4. Contact sheets `contact-pilot-r1.png` (sha `95b896e8…5d80b36`) /
   `contact-pilot-r2.png` (sha `b417b8b7…495a22927`), 2232x956 review
   derivatives built from unaltered raws (proper PNG unfilter decode,
   nearest-neighbor 1/3 point-sample, 440x956 tiles, 8px #EEEEEE gutters);
   review-friendly JPEGs `contact-pilot-r1-review.jpg`
   (`b23aaf2f…4648b1ba`) / `contact-pilot-r2-review.jpg` (`2de032ed…6200ca709`),
   2000x856 via native sips (`-s format jpeg -Z 2000`), verified rendering
   in the read tool + PIL + stdlib unfilter decode + sips dims. Raws remain
   the review source of truth. (Correction 11:53: the first sheet build
   copied still-filtered row bytes and RGB gutters, producing valid-header
   pixel-garbage; rebuilt with a verified round-trip codec. Superseded files
   overwritten in place; raw frames never touched.)
   (Rebuild after the 12:16 history recapture: both sheets rebuilt from
   current raws with the same method; all 5 new tiles match their raws at
   0 diff, stable tiles match the superseded sheets at 0 diff — only the
   history tile changed. Prior `bilinear 1/3` label was wrong: PIL NEAREST
   reproduces all stable tiles exactly, BILINEAR/BOX/sips do not. Prior
   r1-review hash `ff2642cc…` never matched the file on disk; superseded.)

## Reusable Argent flow

`.argent/flows/pilot-live-activity-lockscreen.yaml` (fragment): lock/wake
button pair + full-res screenshot evidence step. Recorded on the real r1
walkthrough; polished post-finish (prompt-specific waits/tap removed:
one-time interstitial with varying text, unreplayable; live handling above
is the record). Audit greps clean (no coords/roles/device-ids/loose
conditions/fixed waits). Quirk found while polishing: the Lock Screen serves
no runner tree, so `when:` guards error there — flow is deliberately
procedural with human-evidence screenshots; no destination identity assert
exists (no stable lock-screen selector: date/time change, Home indicator has
no text/id). Two consecutive full passes of unchanged YAML: PASS, PASS
(device DC79, explicit).

## Teardown / restore (post-run)

- Every frame teardown `complete`; chrome restored exactly
  (appearance light, content_size large); status_bar override cleared
  (session-owned, clean snapshot).
- No capture-owned Live Activities remain (both ended via ack-verified
  cleanup). No production state touched (capture-only sim + namespace).
- simulator-server stopped scoped to DC79 only at session end; retained
  assets stay on disk.

## Addendum 11:53 — QA process deviation (coordinate taps) + date artifact path

- **Deviation, recorded honestly:** during the r2 LA walkthrough, three taps
  aimed at the lock-screen "Always Allow" button were estimated from
  downscaled screenshots ((0.70, 0.587), (0.70, 0.595), (0.71, 0.602)),
  against the strict never-guess-tap-coordinates rule. This is a process
  deviation; no waiver is requested, no approval inferred, and not all
  actions are claimed rule-compliant. Future work uses tree-derived points
  only. Observed outcome of the misses: the prompt persisted, the live timer
  kept running (12:46 → 13:07 across the attempts), capture state stayed
  ready, no app control changed state (Stop was not activated, categories
  unchanged). No side effects were observed; unknown side effects are
  unknown. The fourth tap at the exact fresh-tree point (0.7235, 0.828)
  granted Always Allow and is the evidenced action. The failed attempts are
  preserved in this history, not cleaned up.
- **Date artifact path (no fix applied):** the "Saturday, 1 January" lock
  date is reproducible and PNG-visible in both runs. A potential path is the
  full-ISO `status_bar` override carrying the reference Tuesday date (native
  CLI help advertises an ISO date form), but before any date fix the runner
  owner records a test/change and recaptures the affected frame; no raw
  image editing, ever. Nothing was changed for this; main notes the artifact
  in the draft user review.

## Addendum — contact rebuild from recaptured history (no captures, no device)

- History raws changed under the retained root (`history.png` 12:16:14 /
  12:16:44, hashes `b4cc904f…` / `d2da6b4c…` matching both run-manifests);
  all other raws byte-identical to their manifests. The superseded sheets
  (PNG `818667ea…` / `56b916f0…`) showed the pre-12:16 History viewport.
- Rebuilt `contact-pilot-r1.png` (`95b896e8…5d80b36`) /
  `contact-pilot-r2.png` (`b417b8b7…495a22927`), 2232x956 RGBA, and
  `contact-pilot-r1-review.jpg` (`b23aaf2f…4648b1ba`) /
  `contact-pilot-r2-review.jpg` (`2de032ed…6200ca709`), 2000x856 JPEG —
  overwritten in place; raws never touched, no sim/device/xcodebuild, no
  commits.
- Method (same as the superseded sheets): PIL proper PNG decode, NEAREST
  1320x2868→440x956, story order Track/Insights/History/Picker/Live-Activity,
  8px #EEEEEE gutters; JPEGs via `sips -s format jpeg -Z 2000`.
- Verify: new PNGs decode via stdlib unfilter (956/956 rows), PIL, and sips
  dims; new JPEGs decode via PIL and render in the read tool (History tile
  now shows Oct 14–11 + Deep work notes glyph; r1 History status bar has no
  black pill, r2 does). All 5 new tiles match current raws at 0 diff;
  the 4 stable tiles match the superseded sheets at 0 diff.

## Addendum 2026-10-30 PM — expansion QA (tasks 6.3/6.5): contact sheets + clipping review

QA worker record, no captures, no device manipulation, no `xcodebuild`, no
source edits, no commits. All work is review-derivative (PIL/sips/NumPy reads
of retained PNGs + JSON) plus 32 new external review files. Raws never
touched. This section reports DELIVERED + REVIEWED state only; it is not
owner approval (tasks 5.4-gated expansion acceptance stays with the owner at
6.6; nothing here approves any asset).

### 1. Contact sheets built (16 missing; iPad already complete)

Method byte-verified before building: rebuilt the three existing templates
from current raws (PIL proper PNG decode, NEAREST downscale, story order,
8px #EEEEEE gutters, RGB) and reproduced them byte-identically —
`contact-pilot27-r2.png` (`2837c45c…c6b2a4`), `contact-en-65-r1.png`
(`1ae78110…89c9b2`), `contact-en-ipad13-r1.png` (`8ee22ed6…477867e`).
Same code path then built the missing sheets; JPEG review derivatives via
native `sips -s format jpeg -Z 2000`, PIL-render-verified.

- 6.9 (1320x2868 → 440x956 tiles, 7 frames Track/Insights/History/Add-entry/
  LA-Lock/LA-compact/LA-expanded, sheet 3128x956, review JPEG 2000x611):
  - `contact-ru-r1.png` `defecd63…f64615` / `-review.jpg` `12d55333…504ea`
  - `contact-ru-r2.png` `93195f15…4d2718` / `-review.jpg` `6d7d643a…383e3383`
  - `contact-zh-Hans-r1.png` `ca385174…1e75ed` / `-review.jpg` `6de89ba3…c2c472`
  - `contact-zh-Hans-r2.png` `bead4253…50bccb` / `-review.jpg` `31e2dbae…85f63`
  - `contact-es-419-r1.png` `62481c35…4e683a` / `-review.jpg` `98c6f74e…4c4f8175`
  - `contact-es-419-r2.png` `3f2002fd…a13964` / `-review.jpg` `ef2cb7d7…2f286cda`
  - `contact-pt-BR-r1.png` `79e3a6f6…f52e3c` / `-review.jpg` `81387604…7d7e5b08ac`
  - `contact-pt-BR-r2.png` `9bf76d7f…4261f6` / `-review.jpg` `8f94daa9…a779ec0f4d`
- 6.5 (1242x2688 → 414x896 tiles, 5 frames Track/Insights/History/Add-entry/
  LA-Lock, island N/A by design, sheet 2102x896, review JPEG 2000x852):
  - `contact-ru-65-r1.png` `8cbaacea…fee079` / `-review.jpg` `b93f1a1b…0b5b0b9b`
  - `contact-ru-65-r2.png` `cef93378…a3889b` / `-review.jpg` `f324a597…e64abda3bb`
  - `contact-zh-Hans-65-r1.png` `b9cfbe93…d577fb` / `-review.jpg` `39d73850…b03207d6`
  - `contact-zh-Hans-65-r2.png` `d4d34a6e…feee39` / `-review.jpg` `a2ab7b76…7406aa489`
  - `contact-es-419-65-r1.png` `f0e8fd09…5a09e7` / `-review.jpg` `5ce0d018…cafdad9`
  - `contact-es-419-65-r2.png` `72547954…fd30ec` / `-review.jpg` `856658d4…827de1ca`
  - `contact-pt-BR-65-r1.png` `8c83028e…a87c3b` / `-review.jpg` `27491bf6…5ad1afbb`
  - `contact-pt-BR-65-r2.png` `ccd2aaf9…d00976` / `-review.jpg` `c4a914b6…1757b407`
- Verify: all 16 raws native-size (`sips`-equivalent PIL dims); all 6.9 raw
  sha256 match their run-manifest `screenshot_sha256` (8/8 manifests);
  spot tile checks `contact-pt-BR-r2.png` (7/7 tiles) + `contact-es-419-65-r1.png`
  (5/5 tiles) match downscaled raws at 0 diff. en-65 / en-iPad13 / pilot27 /
  all-5-locale-iPad sheets pre-existed and were re-verified by the same
  reproduce-check (above), not rebuilt.
- Nomenclature: `contact-<run>.png` matches the run dir (`ru-r1`,
  `ru-65-r1`, …), consistent with existing `contact-en-65-r1.png`.

### 2. Provenance notes (read, not created)

- 6.9 non-en manifests `status complete` EXCEPT `ru-r1` and `zh-Hans-r1`
  (`status needs-inspection`, `pending_evidence ["la-expanded: teardown not
  complete: real activity … not in ended_activity_ids: a capture-owned banner
  may still be live"]`). r2 of both locales is `complete` with `[]`.
  Owner disposition pending at 6.6; QA did not end or touch any activity.
- 6.5 runs have NO `run-manifest.json` (per-frame `sessions/*.json` +
  `requests/*.capture-request.json` only); en-65 contacts pre-existed. 6.6
  manifest assembly stays with the capture owner.
- iPad `*-two-runs.json` files report `needs-inspection` with
  `unreviewed_variance` (owner clears per-frame; never auto-passed).
- Deck totals: `shot-cat-food 41400` live in all manifests checked; ru week
  `12300` (Monday-first) vs `23100` elsewhere, today `4500`, all `198600`
  everywhere — matches design week-rule `locale-native`, not a defect.
  ru Insights therefore renders `3 ч 25 мин` with fewer week category rows;
  by design.

### 3. Clipping/truncation review (es/pt priority, all sizes)

Viewed: all 8 new 6.9 + all 8 new 6.5 review JPEGs, all 5 iPad r1 review
JPEGs, `contact-en-65-r1-review.jpg`; full-res spot reads: pt-BR-r2
insights/add-entry, es-419-r2 insights/add-entry/history/track-running,
es-419-ipad13-r1 add-entry, en-ipad13-r1 add-entry + sheet-bottom crops for
all 5 iPad locales. Findings:

- **No clipping/truncation in any iPhone frame, any locale, either size.**
  Insights footnotes fully visible incl. ru 2-line wrap
  (`Запись с несколькими категориями учитывается в каждой из них.`);
  History Today/Yesterday day totals + newest-first order correct;
  multi-category rows (`Vive Latino / Entretenimiento, Pasatiempo`,
  `Virada Cultural / Entretenimento, Hobby`, `Пикник Афиши / Развлечения,
  Хобби`) fit; Add-entry all 5 cards + notes values visible on iPhone
  (es `Saqué la cola sin conexión`, pt `Subi a fila offline`, ru
  `Офлайн-очередь отправлена`, zh `离线队列已上线`, en `Shipped the offline
  queue`); category chips + `Añadir/Adicionar/Добавить/添加` fit;
  compact-timer names fit (`Carrera/Corrida matinal`, `Утренняя пробежка`,
  `晨跑`); LA faces correct per-locale Stop (`Detener`, `Parar`, `Стоп`,
  `停止`, `Stop`) with matching name + first-category chip (pt-BR-r2
  expanded `Parar` re-verified — appex fix holds on the 6.9 stores sets).
- pt-BR Insights/tab title renders `Insights` (English). Verified by design:
  bundle string `tab.insights = "Insights"` in `pt-BR.lproj` (es-419 uses
  `Análisis`, ru `Аналитика`, zh `洞察`). Not a capture defect; owner
  already ships this string.
- iPad centered-column layout accepted per owner; iPad status bar shows the
  real date (`Fri 30 Oct`, no 9:41 override) — accepted per owner. No
  clipping in iPad Track/Insights/History/Lock frames at sheet scale.
- **iPad Add-entry Notes inconsistency (finding for 6.6):** Notes card
  status differs by locale at identical pipeline — en + zh show the Notes
  label + value PEEKING but clipped by the sheet's bottom edge (en `Notes /
  Shipped the offline queue`, zh `备注 / 离线队列已上线`); ru/es/pt end
  after the Categorías card (`+ Добавить/Añadir/Adicionar categoría`) with
  Notes fully below fold (0 dark-text px below y=2100 in x400–1660 on all 10
  iPad add-entry frames; sheet bottom edge y=2035 at center column in all
  10). iPhone sets show all 5 cards cleanly. Owner decides at 6.6: accept,
  or standardize scroll/recapture (capture-owner scope; QA did not
  recapture). No data loss — notes values exist in deck/session provenance.
- Prior disclosed artifacts persist in expansion sets, unchanged in kind:
  Lock-Screen `Saturday, 1 January` date (status-bar-override side effect,
  owner-accepted at 5.4) and real device-local times on home-screen status
  bars / banner-adjacent clocks (accepted at 5.4).

### 4. Cross-run numeric comparison (r1 vs r2, raw pixels)

Full-matrix raw diff (r1 vs r2, per frame; LA frames numeric-only by rule,
never pixel-compared for approval):

- history: byte-IDENTICAL on all four 6.9 non-en sets; ≤389 px (≤0.01%,
  compact-timer/stop-button edge) on 6.5/iPad. Top-viewport content stable.
- insights: byte-IDENTICAL on all 6.9 sets + ru/zh-65; ≤106 px 6.5 / ≤4 px
  iPad elsewhere. Stable.
- track-running: IDENTICAL except three runs — es-419-r2 and pt-BR-r2 (6.9:
  blue started-caption 48 px lower, same x/width/pixel-count: es y925→973,
  pt y926→974; big timer + all else identical) and ru-65-r2 (caption 38 px
  lower, y872→910, PLUS whole-content vertical doubling in the diff mask:
  217982 px / 6.53%, maxabs 245, bbox x70–1170 y557–2256 — timer digits,
  caption ×2, name field, Stop, chips all doubled). Content identical in all
  three (same strings, totals, selection); only vertical placement differs.
  All other track pairs (incl. pilot27 en, ru/zh-6.9, en/es/pt/zh-65, all
  iPad) byte-identical. Root cause not determined by QA (no layout
  knowledge claimed); owner disposition at 6.6 which position is canonical.
- add-entry: differs in EVERY pair (0.04–0.18%, 2–7k px, maxabs ≤16,
  confined to the Name-card band, e.g. es-65 x55–1186 y190–356) —
  sub-perceptual sheet/text-render jitter, content identical. Not a
  blocker; recorded so 6.6 does not mistake it for instability.
- la-compact: 400–1250 px (timer digits in island; expected live-timer
  variance). la-expanded: small everywhere except pt-BR-r1-vs-r2 44474 px
  (island timer 13:54 vs 12:44 + home-screen real-time status clock —
  per-run wall lengths differ; see §5, not a defect).
- la-lock: all pairs differ (live banner timers + transient lock state).
  Wallpaper mid/low bands byte-stable across r1/r2 EXCEPT `zh-Hans-65`
  (55.60% strong-diff, mid-band mean 44.4 — full-frame different lock
  wallpaper between r1 13:19-banner and r2 13:07-banner; flag for 6.6).
  ru/zh-6.9 top bands differ mildly (1.38%/1.64%: r1 has NO Dynamic-Island
  black pill + no `Swipe up to open`, r2 has pill + lock badge + hint;
  clock 09:41 + wallpaper swirls identical). es/pt-6.9 + all other lock
  pairs share wallpaper (≤0.78%). All banners genuine with correct per-run
  timers (§5).

### 5. Live-timer numeric validation (all 50 LA frames, 25 runs)

`capture_window` (started_at, captured_at_iso, observed_elapsed_s) from each
`runs/*/frames/la-*.json`: |wall − observed| ≤ 2.0 s on ALL 50 frames
(max 2.0 exactly once, pt-BR-ipad13-r2; rest ≤1.9). Independently
re-read 8 banners from pixels — ru-r1 lock 13:08=788 ✓, ru-r2 12:54=774 ✓,
zh-65-r1 13:19=799 ✓, zh-65-r2 13:07=787 ✓, es-419-r2 lock 13:07=787 ✓,
pt-BR-65-r2 lock 13:03=783 ✓, pt-BR-r1 expanded 13:54=834 ✓, pt-BR-r2
expanded 12:44=764 ✓ — all match recorded `observed_elapsed_s`. No mocked
timers; LA genuineness (Lock banner required everywhere incl. 6.5/iPad;
compact + expanded on 6.9 Island class) confirmed present in every set.

### 6. 13 mini + SE3 XXXL fit checks — recorded limitation (not performed)

`xcrun simctl list` (read-only) shows `13mini-iOS27-track`
(`2CC6132D-…`, Shutdown) and `SE3-iOS27-track` (`03DEF264-…`, Shutdown) on
the iOS 27 runtime, but QA ran no `xcodebuild`, booted nothing, installed
nothing, and changed no Dynamic Type setting — per QA scope (capture +
build + device manipulation belong to the capture owner; prior QA precedent
also ran no builds). Repeating the archive-change's 13 mini / SE3 XXXL
fit-check procedure therefore stays open under task 6.5 for the capture
owner (or a follow-up QA pass with an explicit device mandate). No claim
made about XXXL or smallest-screen fit beyond the captured 6.9/6.5/iPad
geometries at Large type.

### 7. Standing variances for 6.6 (unchanged, restated)

ru-r1 + zh-Hans-r1 `needs-inspection` teardown flags (§2); 6.5 sets lack
run-manifests (assembly pending); iPad two-runs `needs-inspection`
(unreviewed_variance, owner-cleared); iPad Notes peek/hidden split + en/zh
clip-at-edge (§3); track caption/content vertical offsets in es-419-r2,
pt-BR-r2, ru-65-r2 (§4); zh-65 lock-wallpaper change + ru/zh lock top-state
differences (§4); add-entry sub-perceptual jitter everywhere (§4). No
blockers reproduced by QA beyond these recorded findings; no fix applied
(QA scope: no code, no recapture, no commits).
