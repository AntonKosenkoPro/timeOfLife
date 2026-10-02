## Why

`flexibleBool` (`backend/internal/apple/verifier.go:45-57`) accepts `true`/`"true"`/`1` → true and `false`/`"false"`/`0`/null → false, and returns an error for any other shape — so unknown `email_verified` claim shapes fail verification loudly (`ErrInvalidToken` → 401 `invalid_apple_token`) instead of silently downgrading to false. Issue #96 tracks the decision: keep fail-closed. The twist is that `AppleSignIn` (`handlers/auth.go:410-464`) today issues sessions with `emailVerified=true` unconditionally ("Apple users are considered email-verified"), so fail-closed vs. downgrade currently changes availability only, not trust — the strictness is future-proofing for when `IsEmailVerified()` gates something.

## What Changes

- Pin the fail-closed behavior by tests: a garbage `email_verified` shape (e.g. `"yes"`, `2`, `{}`) → token verification error → 401 `invalid_apple_token`.
- Pin that all known wire shapes are unchanged: `true`/`"true"`/`1` → verified; `false`/`"false"`/`0`/null → unverified (parse OK).
- Add a test comment noting `AppleSignIn` currently issues `emailVerified=true` regardless, so today's stakes are availability (reject vs. accept the token), not trust escalation.
- Document in the spec delta that the parsed value is currently unused by the handler.
- Non-goals: no handler change (`AppleSignIn` untouched); no change to RS256 + iss + aud + exp + 30s leeway + sub validation; no change to 503 `apple_not_configured` gating or rate limiting; no iOS change.

## Capabilities

### New Capabilities

(none.)

### Modified Capabilities

- `apple-signin`: pin fail-closed parsing of unknown `email_verified` claim shapes (garbage → 401) and record that the value is currently unused by the handler.

## Impact

- Backend: `backend/internal/apple/verifier.go` (tests only — behavior already fail-closed); no `handlers/auth.go` change.
- iOS: none.
- Docs: spec delta on `apple-signin` only; no OpenAPI change; no FURPS change.
- Authoritative docs: `openspec/specs/apple-signin/spec.md` (endpoint contract); Apple identity-token JWT contract (already-implemented RS256/JWKS path — no new external dependency, no ctx7 fetch).
