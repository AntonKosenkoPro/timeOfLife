## Why

Issue #40 asks for the running timer to stay visible in the Dynamic Island (with Mac streaming as the free side-effect of Live Activities on same-iCloud devices). Today the running timer exists only inside the app (Track readout + cross-tab `CompactTimer`); once the user leaves the app there is no glanceable surface. Milestone: TestFlight public release.

## What Changes

- New Widget Extension target (XcodeGen `project.yml`) hosting an ActivityKit `ActivityConfiguration` for the running timer.
- `TimerAttributes` (static: exact text + first-category icon) + `ContentState` (dynamic: `startedAt`) per ActivityKit split; `request()` on Start (foreground only, gated on `areActivitiesEnabled`), `end()` on Stop.
- Four Island faces + Lock Screen banner, all ticking via system `Text(timerInterval:)` (no per-second `update()`):
  - compact (icon + elapsed), minimal (icon only), expanded (icon + name + elapsed + Stop + Go-to), banner (icon + name + elapsed + Stop).
- Two actions: whole-surface tap deep-links to Track (`lifio://track` via `widgetURL`/`Link`); Stop is an `alwaysAllowed` AppIntent button (expanded + banner only) writing `source='manual'` through `LocalStore` — identical to in-app Stop.
- Ended card: final `✓ Saved <duration>` banner with `.after(TBD)` dismissal (seconds tuned while testing); Island collapses at once. No `pushType` token (local-only).
- Content rule: exact name + first-category icon only — no category names, no "via" labels, no notes, no started-at line.

## Capabilities

### New Capabilities

- `live-activities`: Live Activity lifecycle and presentations for the running timer (request/update/end, four Island faces + banner, Stop intent + Track deep link, dismissal, active-account-only + graceful failure).

### Modified Capabilities

(none — timer behavior, provenance, and sync are unchanged; the Island mirrors `timer_state` and reuses the `manual` stop path.)

## Impact

- `ios/TimeOfLife/project.yml` (new extension target, App Group capability), Widget Extension sources, shared attributes/intent types.
- `TimerService` (request/end hooks), Track stop path (single call site for both stops), `LocalStore.timerDraft` read path shared with the extension.
- New `L10n` keys (Stop, Saved, accessibility labels) in both locales; `Info.plist` deep-link route for `lifio://track`.
- No backend / OpenAPI change. No on-disk format change (pre-release policy).

## Non-goals

- ControlWidget toggle (stays deferred under `lock-screen-controls`; the new extension target does not add one).
- Remote/push updates (`pushType: .token`), multi-activity support (singleton `timer_state` — one activity max), notes/tags editing from the Island.
- Final dismissal seconds (tunable during testing), category names or provenance on any face, lock-screen privacy toggle (default show; follow-up if requested).

## External docs

- ctx7 `/websites/developer_apple_activitykit` — queries: "Live Activity lifecycle states active stale ended dismissed", "implement Live Activity ActivityConfiguration Dynamic Island Lock Screen", "open app from Live Activity widgetURL Link tap", "interactive button AppIntent Live Activity end dismissalPolicy". Version pin: iOS 18 SDK via Xcode 16+ (deployment floor 18.0, no availability guards).

## Affected baselines

- `timer-capture-experience` (External-stop reconciliation already covers a draft vanishing under Track — reused, not modified).
- `lock-screen-controls` (closest kin: `alwaysAllowed` intent, active-account-only, graceful cold-boot failure — pattern reused, spec untouched).
- `entry-provenance` (`manual` shows nothing — reused, no new source value).
- `local-first-store` (`timer_state` singleton in App Group — read shared with extension, writes stay in `LocalStore`).
