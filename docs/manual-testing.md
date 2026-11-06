# Manual testing (device smoke checklists)

Unit tests fake the Apple authorization (`AppleAuthorizationProviding`) and can't reach Apple's JWKS or the Dynamic Island, so the checklists below must be verified manually on a **real device**. Run them before any release that touches auth or Live Activities, and after the `release.yml verify` job is green — do not distribute the TestFlight build until both are green.

## Sign in with Apple

Apple's identity-token JWKS is only fetched for real with `APPLE_CLIENT_ID` configured (the entitlement has no effect in the simulator).

Prerequisites: Release build installed on the device (`Product → Destination → your device`, Release scheme archive or Run with Release config), backend reachable with `APPLE_CLIENT_ID=com.antonkosenko.timeoflifeapp` (local or production), a sandbox/production Apple ID.

1. [ ] **Sheet presents** — launch the app (signed-out, the auth flow is the root screen) → tap *Sign in with Apple*; Apple's native authorization sheet appears (not an error).
2. [ ] **Sign-in succeeds** — complete the sheet (try a *Hide My Email* address); the app lands in the shell; Profile shows the session and "Sync now".
3. [ ] **Backend verified the token** — backend log shows the Apple sign-in line for the user (JWKS fetched, `aud` matched); the relay address `*@privaterelay.appleid.com` is stored as the email with `email_verified=true`.
4. [ ] **Sync works** — start/stop a timer, run "Sync now"; the entry appears on the relay (check via a second sign-in on another device/simulator, or the backend DB).
5. [ ] **Per-user resume** — with entries + a running timer on device A, log out and log back in as the **same** account: the file reopens and resumes (entries list intact, timer draft resumes, outbox drains without a re-pull). Logging in as a **different** account opens that account's own file (no cross-account data). Log out and confirm the dormant file is kept (no wipe); only the explicit per-account Erase deletes the active file.
6. [ ] **Revoked session locks, never wipes** — force a server-side revocation of device A's refresh family (reuse detection via a replayed refresh token, a TTL-expired refresh, or a logout-revoked token): the app returns to the auth gate; all local data (entries, categories, timer draft, outbox) is intact. Re-authenticating reopens and resumes the same account file. Logging out of device B must **not** lock or affect device A's session (per-device logout).
7. [ ] **Cancel is silent** — start the Apple flow, dismiss the sheet; no error banner appears.
8. [ ] **Offline gates the button** — airplane mode on; the Apple button is disabled (dimmed); the email path still navigates.
9. [ ] **Idempotent re-sign-in** — sign out, sign in with Apple again; same user (the same account file reattaches, no duplicate account or duplicate seeded categories).
10. [ ] **Hide My Email attribution (email-OTP path)** — on Continue with Email, the system Hide My Email sheet attributes to Lifio (never a numeric PID); the saved alias label in Settings → Apple Account → iCloud → Hide My Email agrees. Requires the `webcredentials:antonkosenko.pro` association verified (`swcd`).

## App Review access (normal screens, local/test backend)

No Design/L10n changes are expected: the shipping six-digit field, 30-second resend cooldown, and `invalid_otp` / `rate_limited` error mapping are reused unchanged. Run against a **local/test backend with a synthetic review binding** (never production budgets or credentials). Prerequisites: backend running locally with the full `REVIEW_*` binding for a synthetic verified email-created account; the iOS app pointed at it (Debug config, `http://127.0.0.1:8080`).

1. [ ] **Repeated login** — sign in with the review email + code on two devices/simulators; both land in the shell. Repeat after ordinary OTP TTL would have elapsed (10m); both succeed with no new request.
2. [ ] **Resend changes nothing** — on the code screen, wait out the 30s cooldown and resend; the request returns 202, no new email arrives, and the same code still signs in.
3. [ ] **Wrong code** — submit an incorrect code; the localized `invalid_otp` banner appears (all five locales if copy changed — none expected).
4. [ ] **Throttled** — exhaust the budgets (5 quick attempts); the next verify returns `429 rate_limited` with the localized message and a `Retry-After` header; the app shows the rate-limited banner.
5. [ ] **Two-device independence** — with both devices signed in, sign out on one; the other stays signed in with working sync.
6. [ ] **Ordinary sync/isolation** — create entries on the review account, run "Sync now"; they appear on the relay for that account only. Sign in as a different account; no cross-account data is visible.
7. [ ] **Deletion** — delete the review account from Profile → Account; the purge removes content, sessions, and attempt history. The same code no longer signs in (stays `invalid_otp`); re-registering the email creates a new UUID that the old code does not authorize.
8. [ ] **Rotation/disablement** — after a verifier rotation, the old code fails and the new code works. After disablement, the address restores ordinary mailed OTP (request sends an email; the old review code fails).
9. [ ] **Refresh revocation** — run the operator `revoke` command for the review UUID; the next refresh on every device fails and each device returns to the auth gate with local data intact (lock-not-wipe).

## Live Activities

Live Activities need a real device with Dynamic Island (the simulator shows the Lock Screen banner only) and a signed-in account with at least one category. The "compact"/"minimal" faces below are system Live Activity presentations — unrelated to the removed in-app compact timer (History/Insights render no in-app timer surface since `remove-compact-timer`).

1. [ ] **Island appears** — start a timer on Track; the Dynamic Island shows the compact face (first-category icon + ticking elapsed).
2. [ ] **Expanded card** — long-press the Island; the expanded card shows the exact name, icon, elapsed, Stop, and Go-to-Track.
3. [ ] **Go to Track** — tap the compact face (or the Go row); the app opens on the Track tab with the timer running.
4. [ ] **Stop from the Island** — stop from the expanded card or the Lock Screen banner; the entry saves with no "via" label, the banner shows the Saved card with the final duration, then dismisses within seconds and the Island collapses.
5. [ ] **Minimal face** — with music (or another Live Activity) active, the timer collapses to the icon-only minimal face without layout breakage.
6. [ ] **Lock Screen banner** — lock the device while running; the banner shows icon + name + ticking elapsed + Stop.
7. [ ] **Dismissal delay** — confirm the Saved card lingers long enough to read but never minutes; record the final seconds in the change's spec delta (task 5.1).
