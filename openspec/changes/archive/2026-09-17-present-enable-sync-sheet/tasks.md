## 1. Restore-then-present branching (the dead tap)

- [x] 1.1 Add a focused testable seam for the Enable Sync tap (e.g. an `EnableSyncPresenter` with injected restore + signed-in reader and a published sheet flag): on tap, run `restoreSession()`, present the sheet iff still signed out; disable the row while the restore Task runs.
- [x] 1.2 SwiftTesting coverage: restore-signs-in → no sheet; restore-noop (no tokens) → sheet presented; already-signed-in → no-op.
- [x] 1.3 Wire `ProfileView`: replace the bare `restoreSession()` button action with the seam; present `AuthFlowView` in a `.sheet` with `environmentObject(container)`; keep `ProfileEnableSyncButton` identifier.

## 2. Sheet chrome and dismissal

- [x] 2.1 Add Cancel close (`cancellationAction` toolbar item on the sheet) + auto-dismiss on `.signedIn` (via an `isSignedIn` mapping); swipe-to-dismiss keeps working with local data untouched.
- [x] 2.2 SwiftTesting coverage: sign-in flip dismisses (presenter flag clears); cancel path leaves session and store untouched.

## 3. Sync-upgrade copy (EN + RU + L10n)

- [x] 3.1 Add scoped keys (sheet title/subtitle in cross-device-sync voice + Cancel) to `en.lproj` + `ru.lproj` + `L10n`; reword `profile.enableSync*` values only if they read as sign-in-gating (key names stay); extend `LocalizationTests` count/parity.

## 4. Verification and docs

- [x] 4.1 `swiftlint lint --strict` clean; `xcodebuild -scheme TimeOfLife -destination '<available simulator>'` warning-free build; `xcodebuild test` green.
- [x] 4.2 Simulator pass (signed out, no session): Profile → Enable Sync → auth sheet opens; complete email-OTP against dev backend *or* cancel → Profile unsigned, data intact; with a restorable session → signs in with no sheet.
- [x] 4.3 Re-check `Requirements/FURPS/Sign-up_and_Sign-in.md` + `Common.md` rows for conflicts; fix or reconcile (expected: none — presentation only).
- [x] 4.4 Update `docs/project-context.md` "Incomplete / deferred" (Enable Sync presentation is now delivered) + `Design/` only if visuals changed beyond the sheet; no OpenAPI/backend changes.
