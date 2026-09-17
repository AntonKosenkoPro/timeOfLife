# Tasks: Erase Resets Auth Flow

## 1. Implement

- [x] 1.1 In `ProfileView.eraseLocalData`, after the wipe + `AuthService.logout()`, reset the auth navigation path to `[]` (one line on `container.navigation.path`), so the next "Enable Sync" opens `AuthFlowView` at email entry with an empty email field.

## 2. Regression coverage

- [x] 2.1 Note: `eraseLocalData` is a private `ProfileView` function — unit/SwiftTesting coverage of the reset itself is not practical. If a testable seam already exists for the erase action, cover "erase → path is empty" there; otherwise rely explicitly on E2E verification (task 3.2) and say so here. → No seam exists; relied on E2E (3.2 done).

## 3. Verification

- [x] 3.1 `swiftlint lint --strict` clean; warning-free `xcodebuild` build; `xcodebuild test -scheme TimeOfLife -destination '<available simulator>'` green. (0 violations; 522 green.)
- [x] 3.2 Simulator E2E (iPhone SE 1st gen, iOS 15.5 sim): sign in via email-OTP (stale path present) → Profile → "Erase local data" → confirm → "Enable Sync" → sheet opens at email entry with an empty email field, not the stale OTP screen. (Verified 2026-09-17: Welcome root, empty Email field.)
- [x] 3.3 Re-check `Requirements/FURPS/Common.md` (+ `Sign-up_and_Sign-in.md` if erase rows exist) for conflicts; expected: none — navigation reset only. (No erase rows in either file; none.)
- [x] 3.4 Docs check: update `docs/project-context.md` (data plane / sync plane erase wording) if needed; no `Design/`, OpenAPI, or backend changes expected. (Not needed — Enable Sync sheet surface description unchanged.)