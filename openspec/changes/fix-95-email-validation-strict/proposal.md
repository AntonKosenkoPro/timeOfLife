## Why

The server's `validateEmail` (`backend/internal/handlers/auth.go:129-138`) now applies an intersection — length ≤ 254 ∩ `mail.ParseAddress` (with `addr.Address == email`) ∩ legacy regex — so dot-edge inputs (`.a@…`, `a..b@…`, `a.@…`) return 400 where the old regex alone accepted them. The iOS `AuthValidator.isValidEmail` is regex-only and deliberately permissive (server authoritative), so those inputs pass client validation and fail only after submit. FURPS Sign-up U1 says "valid address" without defining strictness. Issue #95 tracks the decision: keep the strict rule and mirror it on iOS, with a lockout check over the users table (expect zero rows, pre-release).

## What Changes

- Pin the server's canonical email rule by tests: the three dot-edge inputs (`.a@example.com`, `a..b@example.com`, `a.@example.com`) → 400; representative valid senders unchanged (200/202 path unaffected).
- Add a one-liner to FURPS Sign-up U1 defining the canonical rule: RFC dot-atom local part, ≤ 254 chars.
- Mirror the three dot rules on iOS (`AuthValidator`): reject leading / trailing / consecutive dots in the local part, hand-rolled (no `net/mail` equivalent in Swift); client and server tests kept in sync.
- Run a lockout proof grep over the users table during implementation (expect zero pre-existing dot-edge addresses); record the result in the change.
- Non-goals: no relaxation of the server rule; no OpenAPI change (`OtpRequest`/`OtpVerify` already `format: email`, `maxLength: 254`); no change to OTP enumeration-closed behavior (always 202 on valid shape); no change to the unified U4 client message text.

## Capabilities

### New Capabilities

- `email-otp-auth`: canonical email-identifier rule for the passwordless OTP path (server validation shape, client mirror, and lockout-free precondition).

### Modified Capabilities

(none — no existing baseline pins the OTP email shape.)

## Impact

- Backend: `backend/internal/handlers/auth.go` `validateEmail` (tests only — behavior already strict); auth handler tests.
- iOS: `Features/Auth/Services/AuthValidator.swift` (add three dot rules) + `AuthValidator` tests; localized strings unchanged (U4 unified message reused).
- Docs: `Requirements/FURPS/Sign-up_and_Sign-in.md` U1 one-liner; `docs/project-context.md` only if routing changes (not expected).
- Authoritative docs: FURPS Sign-up U1; `backend/api/openapi.yaml` (`OtpRequest`/`OtpVerify`); Go stdlib `net/mail` (no new external dependency — no ctx7 fetch; Go 1.24 pins `mail.ParseAddress` semantics).
