There are known problems to fix. Once the problem is fixed, move it to `fixed.md` and remove from here.

Open hardening items from `auth-audit.md` (sign-in/sign-up). The P0 bugs are
fixed (items 9–10 in `fixed.md`); the following P1/P2 items remain. Two of them
(P1-1, P1-2) require production Postgres schema migrations and were held for
review before touching real data.

P1-1. Refresh-token family not tracked → over-broad revocation.
   - `SaveRefreshToken` is always called with `deviceID=""` and there is no
     token `family_id`. On reuse detection the handler calls
     `RevokeAllUserSessions`, so a compromised token on one device logs out
     every device. Fix: add a `family_id` column (migration `003`), reuse the
     family across rotations, and revoke only the family on reuse. Files:
     `backend/internal/handlers/auth.go` (RefreshToken), `backend/internal/db/`.
     (auth-audit P1-1; FURPS R1/S5)

P1-2. Unverified "shadow" accounts created on every OTP request.
   - `RequestOTP` calls `UpsertUser` for any syntactically valid email before
     verification, so every spam/typo/enumeration attempt creates a permanent
     unverified `users` row (unbounded growth + soft enumeration surface). Fix:
     create-on-verify — store the pending OTP keyed by email, create the user
     row only when the code is verified. This reshapes `Store.SaveOTP`/
     `GetValidOTP` (signatures), both DB implementations, the handler flow, and
     the OTP tests. Files: `backend/internal/handlers/auth.go` (RequestOTP,
     VerifyOTP), `backend/internal/db/store.go`, `internal/migrations/003_*`.
     (auth-audit P1-2; FURPS S5/S8)

P1-3. JWT has no `iss`/`aud`; validator doesn't check them.
   - `CreateAccessToken` sets only `sub`/`iat`/`exp`; `ValidateAccessToken`
     doesn't verify `iss`/`aud`/`nbf`. If the HS256 secret is ever shared with
     another token-issuing service, tokens cross-validate. Fix: add `iss`/`aud`
     to `TokenService` config, embed in claims, assert on parse. Files:
     `backend/internal/auth/token.go`. (auth-audit P1-3; FURPS S5/R1)

P1-4. VerifyOTP timing/enumeration side channel.
   - "No such user" returns 401 before any hash work; "wrong code" runs a hash
     compare. Both return the same message but the work/timing differs, making
     user existence weakly distinguishable. Fix: run a dummy `VerifyCode`
     against a fixed hash on the no-user path so the work matches. Pairs with
     P1-2 (create-on-verify changes this flow). Files:
     `backend/internal/handlers/auth.go` (VerifyOTP). (auth-audit P1-4; FURPS R1)

P1-5. OTP email template is still an open TODO (FURPS U5).
   - The magic link + 6-digit code are wired, but the email body template/design
     hasn't been finalised ("find a template of OTP email message or make by
     trying different templates"). Fix: plain-text + HTML template via
     `html/template` with escaping — code prominent, magic-link button, expiry
     note, do-not-reply footer; localised variants if needed. Files:
     `backend/internal/email/sender.go`. (auth-audit P1-5; FURPS U5)

P2-1. `restoreSession` dead code / unused access token.
   - `AuthService.restoreSession` reads `accessToken` from Keychain then
     discards it (`_ = accessToken`). Either remove the read or use it to
     short-circuit `/me` when the JWT `exp` is still in the future. Files:
     `ios/.../Features/Auth/Services/AuthService.swift`. (auth-audit P2-1; S5)

P2-2. `MaxBytesReader(nil, …)` passes a nil ResponseWriter.
   - `decodeJSON` calls `http.MaxBytesReader(nil, r.Body, 1<<16)`. Pass the real
     `http.ResponseWriter` so the limit is reported via the response. Files:
     `backend/internal/handlers/auth.go` (decodeJSON). (auth-audit P2-2; S5)

P2-3. Push auth-package coverage toward 100% (FURPS S3).
   - After the P1 fixes, add tests for each new branch and run `go test -cover`
     on the auth packages to close obvious gaps. (auth-audit P2-3; S3)