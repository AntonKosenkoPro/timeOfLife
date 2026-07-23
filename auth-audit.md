# Sign-in / Sign-up — Hardening Audit

Goal: take the existing passwordless-OTP + Sign-in-with-Apple auth feature from
"works" to production-grade best practice, mapped to `Requirements/FURPS`.

Scope: `backend/internal/{handlers,auth,ratelimit,db,email,apple}` and
`ios/.../Features/Auth` + `ios/.../Core/{Networking,Keychain,Storage}`.

Status legend: the feature already implements passwordless OTP (F1), Sign in with
Apple (F2), access-by-email restore (F3), client+server validation (U1/U2),
autofill + magic-link deep link (U3/U5), resend cooldown, refresh-token rotation
with reuse detection, rate limiting, and email-enumeration prevention. The items
below are the **second-order gaps** that remain.

## Priority tiers

- **P0 — correctness/security bugs** (fix first, small, high value)
- **P1 — best-practice hardening** (FURPS R1/S5/S8)
- **P2 — hygiene/coverage** (FURPS S3/S5)

---

## P0-1 · `extractIP` trusts `X-Forwarded-For` unconditionally — rate-limit bypass
**FURPS:** R1 (secure storage/auth), S5 (best practice)
**Files:** `backend/internal/handlers/auth.go:566-582`

`extractIP` returns the first `X-Forwarded-For` value verbatim. If the server is
not strictly behind a trusted proxy that **overwrites** that header, any client
can set it and get a fresh rate-limit key on every request — defeating the OTP
request, OTP verify, and Apple rate limiters. This is the highest-value gap.

**Fix:** Only honour forwarded headers when a trusted-proxy CIDR allowlist is
configured and `RemoteAddr` is in it; otherwise use `RemoteAddr`. Make the
trusted-proxy list a config value (empty = trust nobody, use RemoteAddr).

**Tests:** `extractIP` unit tests — (a) no trusted proxy → header ignored,
RemoteAddr used; (b) trusted proxy → header honoured; (c) untrusted proxy →
header ignored. Add a handler test that a forged header does not bypass the
OTP-request limiter when no trusted proxy is configured.

---

## P0-2 · `extractIP` mangles IPv6 `RemoteAddr`
**FURPS:** +2/R1
**Files:** `backend/internal/handlers/auth.go:577-581`

`strings.LastIndex(addr, ":")` splits on the last colon, which is wrong for
IPv6 literals like `[::1]:1234` — it returns `::1` truncated mid-address,
producing a bogus rate-limit key (and per-key state never matching). Use
`net.SplitHostPort`.

**Fix:** `host, _, err := net.SplitHostPort(r.RemoteAddr)` with fallback to
`r.RemoteAddr` on error.

**Tests:** `extractIP` unit test for `[::1]:1234`, `127.0.0.1:1234`, and a
bare host without a port.

---

## P0-3 · Concurrent refresh race → mass logout
**FURPS:** R1, U3 (don't sign users out spuriously)
**Files:** `ios/.../Core/Networking/APIClient.swift:72-88`, `ios/.../Features/Auth/Services/AuthService.swift:99-117,122-129`

Two overlapping 401s (e.g. `/me` from `restoreSession` and a parallel authed
request, or several requests fired at once) can each enter the 401 branch and
each call `refreshHandler` → `AuthService.performRefresh`. Because the server
**rotates** the refresh token and revokes the old one, the second refresh sends
the now-revoked token → server reuse detection → `RevokeAllUserSessions` →
**every session for the user is invalidated**. Net effect: the user is logged
out on all devices because of a benign race. This is the classic token-rotation
footgun.

**Fix:** Single-flight refresh. Coalesce concurrent refresh calls onto one
in-flight `Task<String, Error>` so only one network refresh runs; awaiters share
its result. Put the guard in `APIClient` (the retry site) and also ensure
`AuthService.restoreSession`'s manual refresh path goes through the same
coalesced entry point instead of calling `repository.refresh` directly.

**Tests:** `APIClientTests` — two concurrent `send` calls that both get 401
assert that `refreshHandler` is invoked **exactly once** and both calls succeed
with the rotated token. `AuthServiceTests` — `restoreSession` + concurrent
`performRefresh` share one refresh.

---

## P1-1 · Refresh-token family not tracked → over-broad revocation
**FURPS:** R1, S5
**Files:** `backend/internal/handlers/auth.go:329,412,498`; `backend/internal/db/store.go:60`

`SaveRefreshToken` is always called with `deviceID=""`, and the schema has no
token **family** id. On reuse detection the handler calls
`RevokeAllUserSessions`, so a compromised token on one device logs out every
device. Best practice (RFC 6749 §10.4 / OAuth token-rotation guidance): track a
`family_id` set at first issuance and preserved across rotations; on reuse,
revoke only that family.

**Fix:** Add `family_id` column to refresh tokens; `SaveRefreshToken` accepts a
family; rotation reuses the same family; reuse detection revokes by family, not
all-user. Keep `RevokeAllUserSessions` for explicit logout only.

**Tests:** `auth_test.go` — a normal refresh preserves family; reuse of an old
token in family F revokes only tokens in F, leaves an unrelated family F2 alive.

---

## P1-2 · Unverified "shadow" accounts created on every OTP request
**FURPS:** S5, S8
**Files:** `backend/internal/handlers/auth.go:203`

`RequestOTP` calls `UpsertUser` for any syntactically valid email before it is
verified, so every spam/typo/enumeration attempt creates a permanent `users`
row (unverified). This is unbounded growth and a soft enumeration surface.

**Fix:** Defer user creation to `VerifyOTP` (create-on-verify), or keep a
separate `pending_signups` table with a short TTL, or add a GC job for
unverified users older than N days. Create-on-verify is the cleanest.

**Tests:** `auth_test.go` — `RequestOTP` does **not** create a user; successful
`VerifyOTP` creates exactly one verified user; a second verify for the same
email reuses the row.

---

## P1-3 · JWT has no `iss`/`aud`; validator doesn't check them
**FURPS:** S5, R1
**Files:** `backend/internal/auth/token.go:37-75`

`CreateAccessToken` sets `sub`, `iat`, `exp` only; `ValidateAccessToken` doesn't
verify `iss`/`aud`/`nbf`. If the secret is ever shared with another service
issuing HS256 JWTs, tokens cross-validate. Best practice: set `iss` and `aud`
claims and validate them on parse.

**Fix:** Add `iss`/`aud` to `TokenService` config; embed in claims; assert them
in `ValidateAccessToken`.

**Tests:** `token_test.go` — token with wrong `iss`/`aud` is rejected; correct
ones accepted.

---

## P1-4 · VerifyOTP timing/enumeration side channel
**FURPS:** R1
**Files:** `backend/internal/handlers/auth.go:261-303`

"No such user" returns 401 before any hash work; "wrong code" runs a hash
compare. Both return the same message, but the response time and DB-error path
differ, making user existence weakly distinguishable.

**Fix:** On "no user", run a dummy `VerifyCode` against a fixed hash so the work
matches, then return the same `invalid_otp`. (Low severity; pairing with P1-2
create-on-verify changes this flow anyway.)

**Tests:** timing isn't unit-testable cheaply; assert the error code/message is
identical across both paths and that a dummy compare runs.

---

## P1-5 · OTP email template is still open
**FURPS:** U5 (explicit TODO in the requirements doc)
**Files:** `backend/internal/email/sender.go`; `Requirements/FURPS/Sign-up_and_Sign-in.md:10`

FURPS U5 comment: "We should find a template of OTP email message or make by
trying different templates." The magic link + code are wired, but the email body
template/design hasn't been finalised.

**Fix:** Decide on a plain-text + HTML template (code prominently, magic link as
button, expiry note, do-not-reply footer). Render via `html/template` with
escaping; keep the 6-digit code and `timeoflife://verify?code=…` link. Add
localised variants if needed (FURPS U4).

**Tests:** `sender_test.go` — template renders the code and link; HTML-escaping
test; golden snapshot of the body.

---

## P2-1 · `restoreSession` dead code / unused access token
**FURPS:** S5 (minimal code)
**Files:** `ios/.../Features/Auth/Services/AuthService.swift:74,117`

`accessToken` is read from Keychain and then discarded (`_ = accessToken`).
Either use it (skip `/me` when it's still valid by expiry) or remove the read.

**Fix:** Remove the unused read, or use it to short-circuit `/me` when the JWT
`exp` is in the future.

**Tests:** `AuthServiceTests` — when cached access token is unexpired, `/me` is
skipped; when expired, `/me` (then refresh) runs.

---

## P2-2 · `MaxBytesReader(nil, …)` passes nil ResponseWriter
**FURPS:** S5
**Files:** `backend/internal/handlers/auth.go:155`

`http.MaxBytesReader(nil, r.Body, 1<<16)` passes `nil` as the writer. It works
today but the writer is meant to be the real `http.ResponseWriter` so the limit
is reported via the response. Pass `w`.

**Fix:** Thread `w` into `decodeJSON` (it already has access via the caller) and
pass it to `MaxBytesReader`.

**Tests:** `auth_test.go` — oversized body → 400 (already likely covered; verify
the connection-limit path).

---

## P2-3 · Coverage toward S3 (100%)
**FURPS:** S3
**Files:** test suites

Existing tests cover the happy paths and the previously-fixed issues. After the
P0/P1 fixes, ensure each new branch (single-flight, trusted-proxy, family
revocation, create-on-verify, iss/aud) has a test, and run coverage to find
uncovered branches in the auth packages.

**Fix:** Add tests per item above; run `go test -cover` for the auth packages
and close obvious gaps.

---

## Implementation order (proposed)

1. **P0-2** IPv6 `extractIP` — trivial, unblocks correct rate-limit keys.
2. **P0-1** Trusted-proxy `extractIP` — security; builds on P0-2.
3. **P0-3** Single-flight refresh — prevents mass-logout race (iOS).
4. **P1-2** Create-on-verify — removes shadow accounts; reshapes verify flow.
5. **P1-4** VerifyOTP equal-work — pairs with P1-2.
6. **P1-1** Refresh-token family — scoped revocation.
7. **P1-3** JWT iss/aud — token hardening.
8. **P1-5** OTP email template — closes FURPS U5 TODO.
9. **P2-1 / P2-2 / P2-3** hygiene + coverage.

Each item lands as its own commit with tests, mapped back here, and on
verification the entry moves to `fixed.md`.