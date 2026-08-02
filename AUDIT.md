# Codebase Audit — Time of Life

Date: 2026-08-02
Scope: whole repo (backend Go + ios Swift) — refactoring, dead code, simplification, docs drift.
Mode: report only; no files were modified.

## Baselines (all green)

- Backend: `go build`, `go vet`, `gofmt -l` (empty), `golangci-lint run` (0 issues), `go test ./...` PASS.
- iOS: `swiftlint lint --strict` (123 files, 0 violations), `xcodegen generate`, `xcodebuild` (warnings-as-errors) BUILD SUCCEEDED.
- No endpoint/route drift between `backend/api/openapi.yaml`, the chi router, and iOS `CatalogRepository`/`RemoteAuthRepository`.

---

## High — real dead code & contract/production bugs

### Backend (Go)

- **H1. `EmailFromContext` is dead** — `internal/handlers/middleware.go:59`. The email context round-trip is written at middleware.go:47 but never read. Delete it (and the `ContextKeyEmail` write if nothing consumes it).
- **H2. `ErrDuplicateToken` never checked** — `internal/db/errors.go:11`. Wrapped into the save-refresh-token error but no handler does `errors.Is` on it; SQLite never returns it. Handle in `RefreshToken` or remove the sentinel.
- **H3. `Message.From` never set** — `internal/email/sender.go:25`. `NewOTPMessage` never populates `From`, no prod caller sets it. Dead field + dead override branch in `SESSender.Send` (sender.go:182-185).
- **H4. Token-issuance block duplicated 3×** — `internal/handlers/auth.go:314,396,481` (VerifyOTP / AppleSignIn / RefreshToken). Extract `issueTokens(ctx, user, emailVerified)`.
- **H5. Prod container ignores Apple/proxy config** — `docker-compose.prod.yml` maps DB/JWT/EMAIL/OTP/AWS but **omits** `APPLE_CLIENT_ID`, `APPLE_JWKS_URL`, `TRUSTED_PROXIES`, while CI writes `APPLE_CLIENT_ID` into `.env`. **Sign in with Apple cannot work in production.** Add the three envs to the container (and write `APPLE_JWKS_URL`/`TRUSTED_PROXIES` in CI).
- **H6. CI accepts unsupported `EMAIL_BACKEND=mailgun`** — `.github/workflows/backend.yml:158-159` validates against `console|mailgun|ses`, but `config.go:71-73` only accepts `console|ses` (no Mailgun sender exists). Deploy can crashloop. Drop `mailgun`.

### iOS (Swift)

- **H7. Dead localization keys** — `L10n.timerQuickAdd` / `timerActivityLabel` / `timerStopHint` (`.../Localization/String+Localized.swift:42-45`), plus 6 rows across both `.lproj`. Unused; TimerView uses a raw SF symbol instead.
- **H8. `TimerViewModel.didSave` is write-only** (`.../Features/TimeTracking/ViewModels/TimerViewModel.swift:29,133,167`) — set but never read by any view (only a test asserts it). Also `didSelectNewActivity(_:)` is never called (`:98`).
- **H9. `TimeEntry.activityName(lookup:)` unused** — `.../Features/TimeTracking/Models/TimeEntry.swift:22`. Only referenced in its own doc comment.
- **H10. Dead VM/editor code** — `ManageCategoriesViewModel.deleteCategory(_:)` unused (`ManageCategoriesViewModel.swift:150`); `CategoryEditorViewModel` `init(category:store:)` convenience init dead (`CategoryEditorViewModel.swift:72-86`); `CatalogStore.category(named:)` / `CatalogStoring.category(named:)` unused seam (`CatalogStore.swift:16,89`).

---

## Medium — refactor / stale docs

### Backend

- **M1.** `writeAccepted` envelope duplicated 4× — `internal/handlers/auth.go:207,214,221,230`.
- **M2.** Apple reuses the OTP request rate-limit bucket — `internal/server/server.go:82`; cross-feature starvation. Give Apple its own `NewTokenBucket`.
- **M3.** `ended_at` > `started_at` validated 3× — `internal/handlers/entries.go:102,176` + store `ErrEndBeforeStart` (errors.go:38).
- **M4.** SQLite store is a ~965-line test-only parallel double of Postgres — deadcode flags ~40 unreachable funcs. Consider a fake over the `Store` interface, or mark it explicitly test-only.
- **M5.** `minFloat` reinvents Go 1.21 built-in `min` — `internal/ratelimit/ratelimit.go:67`.

### iOS

- **M6.** `AuthService.restoreSession()` reads unused `accessToken` — `.../Features/Auth/Services/AuthService.swift:70,106` (no-op `_ = accessToken`).
- **M7.** `MeasuredBottomBar` + `.onPreferenceChange(BottomBarHeightPreferenceKey.self)` boilerplate duplicated across 5 views — Welcome, TimerView, EmailEntryView, ActivityEditorView, CategoryEditorView. Extract a `.measuredBottomBar { ... }` modifier.
- **M8.** `AnyCodable` decode branches for `.number`/`.bool`/`.array` never produced — `.../Core/Networking/APIClient.swift:198-244`; `DetailsEnvelope` only handles `.string`/`.object`. Narrow to `.null`/`.string`/`.object`.
- **M9.** `Theme.success` color unused — `.../Core/Theme/Theme.swift:15`.

### Docs / consistency

- **M10.** AGENTS.md:145 wrong GHCR image path — `ghcr.io/antonkosenko/time-of-life/backend` vs actual `ghcr.io/antonkosenkopro/timeoflife/backend`.
- **M11.** Test counts stale — README "118" / AGENTS "119", actual **272** `@Test` annotations.
- **M12.** Go "1.22+" → actual 1.24 — `AGENTS.md:51`, `README.md:47` (go.mod, Dockerfile, CI all 1.24).
- **M13.** Dead `.stringsdict` files still shipped — `en.lproj/Localizable.stringsdict` + `ru.lproj` referenced 7× in `project.pbxproj`, but plural moved to Swift suffix keys (`String+Localized.swift`). Delete both + pbxproj refs. RU wording also diverges.
- **M14.** Duplicate validation strings — `L10n.activityValidationNameEmpty/TooLong/NotesTooLong` vs a second `validation.catalog.*` set used via hardcoded `NSLocalizedString` in `CatalogValidator.swift:69-95`. Consolidate on one set.
- **M15.** `openapi.yaml:205-262` documents unreachable 503 `apple_not_configured` — route only registered when `AppleVerifier != nil` (`server.go:141-143`), so unconfigured server never routes. Register always (to surface 503) or drop the 503 from spec.

---

## Low — nits / optional

- **L1.** README entries `notes?` drift — `README.md:141-142` lists `notes?` on entries, but migration `004_drop_entry_notes.sql` removed it and code/OpenAPI agree. Drop from README (AGENTS.md:99 already correct).
- **L2.** `internal/config/config.go:62` panics at startup for short `JWT_SECRET` — return a `configError` instead for consistency with the rest of `Load()`.
- **L3.** `validateNotes` doesn't trim while `validateName` does — `internal/handlers/catalog_validators.go:177-190`. Whitespace-padded notes counted inconsistently.
- **L4.** Test-only exported getters — `MaxAttempts()` (`internal/auth/otp.go:70`), `RefreshTokenTTL()` (`internal/auth/token.go:97`); `Server.handler` field (`internal/server/server.go:100,119`). Trim or expose via test helpers.
- **L5.** `decodeJSON` passes nil `ResponseWriter` to `MaxBytesReader` — `internal/handlers/auth.go:156`. Cosmetic.
- **L6.** Hard-coded user-facing accessibility strings (violate U4/AGENTS.md) — `IconPickerGrid.swift:42`, `SuggestionRow.swift:31-32`, `ColorSwatchGrid.swift:54`, `ActivityRow.swift:98`. Route through `L10n`.
- **L7.** Hard-coded colors used with semantic fills — `TagSelector.swift:43,52`, `TagChip`/`PrimaryButton.swift:57,71`, `IconPickerGrid.swift:38`, `RootView.swift:57`. Consider `Theme.onDanger`/`Theme.buttonLabel` tokens.
- **L8.** `UndoableItem.activityWithEntries(_, entryIds:)` carries unused `entryIds` (always `[]`, discarded at matches) — `UndoBuffer.swift:18,75`, `CatalogService.swift:156,257`. Simplify until Epic 2.
- **L9.** `ScopeConfirmation` attaches its dialog to a `Text("")` — `.../Design/Components/Catalog/ScopeConfirmation.swift:17`. Works; consider background attachment.
- **L10.** `backend/.env` contains real-looking AWS SES credentials — gitignored but live in working tree with `EMAIL_BACKEND=ses`. **Rotate the keys.**
- **L11.** `ActivityIcon` enum has many cases only exercised by `validKeys` in tests — by-design to match the backend union; keep, but note it's a conscious decision.
- **L12.** Localization en/ru parity is OK — `.other` vs `.few/.many` plural differences are correct per `PluralForm`. No action.

---

## Recommended quick wins (small & safe)

- Dead code removal: H1, H3, H7, H8, H9, H10, M1, M5, M9.
- Production correctness: H5 (compose envs), H6 (CI mailgun), L10 (rotate creds).
- Doc/contract drift: L1, M10, M11, M12, M13.
