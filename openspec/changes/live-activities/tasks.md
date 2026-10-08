## 1. Docs and target scaffold

- [x] 1.1 Re-verify ctx7 docs before coding (`/websites/developer_apple_activitykit` — "ActivityConfiguration Dynamic Island", "widgetURL Link deep link", "AppIntent end dismissalPolicy"; pin: iOS 18 SDK via Xcode 16+); implementation tasks depend on this
- [x] 1.2 Add Widget Extension target to `project.yml` (App Group capability, deep-link scheme) + `xcodegen generate`, verify `SystemCapabilities` survive regen (SIWA-incident pattern)
- [x] 1.3 Add `TimerAttributes` + `ContentState` shared types (exact text, first-icon symbol, `startedAt`), unit-tested Codable/Hashable round-trip

## 2. Activity lifecycle

- [x] 2.1 Wire `request()` on timer Start
- [x] 2.2 Wire `end(final Saved content, .after(T))` on every Stop path
- [x] 2.3 Track external-stop reconciliation re-verified
- [x] 2.4 Restore re-mirrors the run (`load()` requests for a persisted draft; singleton-guarded)

## 3. Faces and actions

- [x] 3.1 Implement compact (icon + ticking elapsed), minimal (icon only), expanded (D6), banner
- [x] 3.2 Wire `widgetURL(lifio://track)` on all faces + `Link` Go row in expanded; `RootView` selects Track on URL
- [x] 3.3 Implement Stop `AppIntent`
- [x] 3.4 Localize all new strings
- [x] 3.5 Device-feedback polish: ship strings in the appex (explicit resource files), expanded bottom uses the circular red Stop + plain Track link, Stop hidden outside full-color rendering (D7)
- [x] 3.6 Stop-intent session channel: suite UserDefaults detach from cfprefsd in extensions (device log) — SessionCache mirrors the user id to a group-container sidecar file, resolver reads file-first with defaults fallback, restore re-saves for upgraders
- [x] 3.7 Island stop completion: intent posts a Darwin signal instead of ending (module-distinct attributes type blinds the extension); app reaps orphans with the true duration, reloads tracker surfaces, silent immediate dismiss on catch-up paths

## 4. Quality gates

- [x] 4.1 `swiftlint lint --strict` clean, warning-as-error `xcodebuild` build green
- [x] 4.2 iOS suite green incl. new tests (lifecycle singleton, Stop-intent idempotence, no-anonymous-file, dismissal); re-check FURPS Track rows
- [ ] 4.3 Manual smoke on device: start → Island + banner appear; long-press → expanded; tap → Track; Stop from Island → Saved card → dismiss; competing music activity → minimal; lock screen banner. Precondition: Settings → Face ID & Passcode → Allow Access When Locked → Live Activities ON (else AoD shows placeholders — device-verified, see D7)

## 5. Tuning and docs

- [ ] 5.1 Tune dismissal seconds T on-device (design Q1), record chosen value in spec delta
- [x] 5.3 Pre-archive cleanup (partial): banner SHA marker removed as part of the AoD probe (Profile dual-SHA retained until AoD resolved); TEMP-TEST-10X ticker revert still pending
- [x] 5.2 Update `docs/project-context.md` (Incomplete/deferred entry for Live Activities → shipped), `Design/COMPONENTS.md` if a shared face component is extracted, `README.md` smoke checklist
