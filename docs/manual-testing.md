# Manual testing (device smoke checklists)

Unit tests fake the Apple authorization (`AppleAuthorizationProviding`) and can't reach Apple's JWKS or the Dynamic Island, so the checklists below must be verified manually on a **real device**. Run them before any release that touches auth or Live Activities, and after the `release.yml verify` job is green — do not distribute the TestFlight build until both are green.

## Category defaults

Fresh-install only (already-seeded account files never gain the new starter).

1. [ ] **Eight starters on first seeding** — fresh install, sign in; Manage Categories lists Work, Hobby, Sport, Education, Relax, Sleep, Entertainment, Food with `briefcase`, `paintbrush`, `figure.run`, `book`, `cup.and.saucer`, `bed.double`, `tv`, `fork.knife`. Switch device language across the five supported locales on a fresh install; starter names localize, icons stay the same.
2. [ ] **Compact sports picker** — new category → sports choices are `figure.walk`, `figure.run`, `dumbbell`, `figure.yoga`, `figure.cycling`, `figure.swimming` (no `bicycle` duplicate, no other sports); food choices include `carrot`, child choices include `stroller` and `teddybear`.
3. [ ] **Hidden selection survives editing** — sync a category with a hidden sports icon (e.g. `figure.soccer`), open it, change only the name, save; the stored icon is unchanged and renders its original glyph, not `tag`.
4. [ ] **No backfill** — on a device whose file seeded before this change, sign in after upgrade; no Food category appears and surviving names/icons are unchanged.

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

## My Day planner

Simulator covers layout, sync convergence, and the linked Stop path; the items below need fingers, keyboards, and a real Island.

1. [ ] **Repeated Return** — with software and hardware keyboards, submit several task names in a row; each prepends on top (newest first), the draft clears, focus and the keyboard stay, and the composer never moves.
2. [ ] **Compact screens** — on a small phone (e.g. SE) with the keyboard open, the composer, first rows, and the toolbar progress stay reachable; the Track readout and Start/Stop never shift when counts change.
3. [ ] **Large Dynamic Type** — at the largest accessibility sizes, My Day rows, the composer, and the progress control stay readable and tappable (44 pt targets); scrolling the list never moves the composer.
4. [ ] **VoiceOver reorder** — with VoiceOver on, enter reorder mode via the Reorder toolbar control (no Edit button anywhere) and reorder tasks via the rotor/drag handles; order persists across relaunch and syncs to a second device in the same order. No delete affordances appear in reorder mode.
5. [ ] **Start/Stop frames unchanged** — start and stop linked and ordinary timers on Track; the numeric readout, name row, tag selector, and Start/Stop keep their exact frames (the planner adds toolbar chrome only).
6. [ ] **Immediate running Track** — start a task from My Day; Track presents the running timer at once with no further navigation.
7. [ ] **Two-device convergence** — add/reorder/complete tasks offline on two devices, then sync both; both show the same rows in the same order with both additions and all independent field edits.
8. [ ] **Linked cold-open Live Activity Stop** — start a task from My Day, terminate the app, then Stop from the Island or Lock Screen banner; the app cold-opens, saves the entry, completes exactly that task once, and shows the ordinary Saved card. (Unit + simulator tests cover the path; the Island/banner tap itself is device-only.)
9. [ ] **Row swipes** — drag a row left and right: native Mail-style pills reveal (trailing delete, leading complete/reopen), tapping an action fires it, a deep swipe acts on release, and vertical scrolling still works. There is no edit mode: the Reorder control surfaces drag handles only, with no delete affordances. The running task offers no delete in either mode.
10. [ ] **Instant counts** — cold-open with warm planner data; Track shows the actual done/total counts on first paint with no 0/0 flash.
11. [ ] **Task editor sheet** — tap a task row; the editor sheet opens with the Name, ordered Categories, and Notes fields in that order (the manual entry form minus Start/End: the Name row pushes the shared name picker exactly like the Log Time form — Back discards the picker typing; Notes pushes the shared editor with copy-on-open X/✓). Rename + retag + annotate, save: the row updates in place with no entry change; saving an invalid name or over-limit notes stays open with the draft intact. Editing the running task shows the `In progress` subheader; the bottom delete removes the task into the durable undo buffer and pops the sheet — for the running task the delete is dimmed and the tap shakes the subheader with the reject haptic instead of deleting. Tapping a completed task does nothing; reopen it to edit. Tag and annotate a task, start it: the run carries exactly those tags and notes; an untagged task still inherits exact-text Recents.
12. [ ] **Live linked-Stop counts** — start a task from My Day, Stop on Track; the toolbar control refreshes to the new done/total in place with no navigation, and the icon follows completion (unchecked at 0, checklist partial, checked at N/N).
13. [ ] **Icon states** — with 0 done, some done, and all done (non-empty), the progress control shows `checklist.unchecked`, `checklist`, and `checklist.checked` respectively.
14. [ ] **Notes sync** — annotate a task, sync; a second device shows the notes. Edit notes offline on both devices; both converge per the relay's latest-intent rule with no duplication.
15. [ ] **Live bidirectional sync** — with a linked run active, toggle a category and edit notes on Track: the My Day row follows at once with no navigation. Save category/notes changes on the running task in the sheet: the running draft follows in place with the ticker and locked name untouched (the Live Activity chips follow the set).
16. [ ] **Richer rows** — tagged rows show small icon+name category chips under the task name (cap 2 + `+n`) with the notes indicator trailing them; the running task reads the accent-colored localized `In progress` label instead of Start. A linked run shows no nav-bar subtitle; a non-planner run names itself there (`<name> is in progress now`, item 19). VoiceOver announces name, then categories, then notes; toggle still moves no sibling.
17. [ ] **Chips with categories** — with the keyboard open, each chips-line chip shows its Recent's first category icon; tap one: the composer fills, the line narrows to that chip in the filled-accent selected presentation, and the tap plays the selection haptic; submit: the success haptic plays and the created task carries the full staged set and shows its chips under the name. Clear the draft (×): the full strip returns.
18. [ ] **My Day title and composer** — the page title reads `My Day` (locale-appropriate) with no Edit button anywhere; the Reorder toolbar control toggles drag handles with no delete affordances. The composer shows a persistent leading plus with a contrasting card border in both appearances and under Increase Contrast; the empty hint and counts are unchanged.
19. [ ] **Outside-run subtitle and dismiss** — start an ordinary (non-planner) timer on Track, open My Day: the nav bar reads `<name> is in progress now` under `My Day`. Tap a dimmed Start: the subheader shakes, the reject haptic plays, and nothing starts. Tap the composer dismiss control (or Return on an empty draft): the keyboard dismisses without submitting; a valid Return still never dismisses.

## Live Activities

Live Activities need a real device with Dynamic Island (the simulator shows the Lock Screen banner only) and a signed-in account with at least one category. The "compact"/"minimal" faces below are system Live Activity presentations — unrelated to the removed in-app compact timer (History/Insights render no in-app timer surface since `remove-compact-timer`).

1. [ ] **Island appears** — start a timer on Track; the Dynamic Island shows the compact face (first-category icon + ticking elapsed).
2. [ ] **Expanded card** — long-press the Island; the expanded card shows the exact name, icon, elapsed, Stop, and Go-to-Track.
3. [ ] **Go to Track** — tap the compact face (or the Go row); the app opens on the Track tab with the timer running.
4. [ ] **Stop from the Island** — stop from the expanded card or the Lock Screen banner; the entry saves with no "via" label, the banner shows the Saved card with the final duration, then dismisses within seconds and the Island collapses.
5. [ ] **Dirty-notes Stop** — with the running-notes editor open and unconfirmed text (typed, including a clear; already-✓-confirmed text must NOT prompt), stop from the expanded card or banner: the entry still saves immediately with the confirmed notes and the recorded end time, the Saved card shows and dismisses on its normal schedule, then the app offers **Review Notes** (non-destructive) / **Discard Changes** (destructive, system red, native placement — no fixed side asserted). Review opens the retained editable text without writing; ✓ saves it to that exact entry (History/Insights converge after). Discard — or X/back from review — keeps the confirmed notes with the timer stopped. Background the app with the prompt or review open and return: the text is still there for the same entry. Clean and already-confirmed notes stop with no prompt.
6. [ ] **Minimal face** — with music (or another Live Activity) active, the timer collapses to the icon-only minimal face without layout breakage.
6. [ ] **Lock Screen banner** — lock the device while running; the banner shows icon + name + ticking elapsed + Stop.
7. [ ] **Dismissal delay** — confirm the Saved card lingers long enough to read but never minutes; record the final seconds in the change's spec delta (task 5.1).

## Database suspension safety (real device)

Regression target: `RUNNINGBOARD 0xdead10cc` (file/SQLite lock held during suspension), observed in TestFlight 0.2.8 (152–153). Simulator lifecycle tests cover lock coordination, not the OS-enforced device kill. Use synthetic data and a test account; record device/OS/build, timestamps, and results in the change evidence. Run without a debugger attached, which can change suspension behavior.

1. [ ] **Reload overlap** — with enough synthetic entries to exercise Track/History loads, start sync, immediately go Home or lock the phone, leave it backgrounded, then return. Repeat with the timer running and stopped; check for new `0xdead10cc` reports in device diagnostics/Xcode Organizer.
2. [ ] **Durable state** — confirm the running timer resumes with its original start, saved entries remain present, and pending changes sync once. Separately, while offline, verify a buffered deletion remains undoable after background/foreground (backgrounding itself must not commit it; an existing successful sync push still may).
3. [ ] **Background cleanup** — when the system actually grants the existing Live Activity cleanup task, verify it finishes or expires without retaining a database lock or fabricating a Saved card. If the OS does not grant a run, record this check as not exercised, not passed.
4. [ ] **Account isolation** — background/return, sign out, and sign in as another test account; no prior account content appears and returning to the original account preserves its draft/outbox.
5. [ ] **Cold return** — terminate and relaunch after backgrounding; verify persisted state and Live Activity Stop-link handling remain correct. Cold launch may commit buffered deletions under the existing undo contract; simple backgrounding must not.
