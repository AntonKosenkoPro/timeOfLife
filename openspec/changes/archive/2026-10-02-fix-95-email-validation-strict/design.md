## Context

See proposal.md (Why) for motivation. Current state: `validateEmail` in `backend/internal/handlers/auth.go:129-138` is already strict (length ∩ `mail.ParseAddress` + identity check ∩ legacy regex) with a comment pointing at #95; `AuthValidator.isValidEmail` (`ios/TimeOfLife/TimeOfLife/Features/Auth/Services/AuthValidator.swift:63-66`) is regex-only and deliberately permissive. The specs in `specs/email-otp-auth/spec.md` pin the strict rule, the client mirror, and the lockout-free precondition. Constraints from `docs/project-context.md`: server is authoritative for auth; iOS strings go to both `en.lproj` and `ru.lproj` + `L10n` (U4 — reused as-is, no new strings); OpenAPI is the authoritative API contract (S10 — already `format: email`, `maxLength: 254`, no change); no backward compat needed for on-disk formats (pre-release).

## Goals / Non-Goals

**Goals:**

- Pin the already-strict server behavior with regression tests so the #95 decision survives future refactors.
- Give instant client feedback for the three dot-edge shapes without weakening the server.
- Record the lockout proof so strictness ships justified.

**Non-Goals:**

- No new validation library on either side; no change to the unified U4 message text; no OTP rate-limit, enumeration, or expiry changes.

## Decisions

- **Decision: keep the intersection, don't simplify to regex-or-parser alone.** The three-way intersection is what rejects the dot-edge inputs (`mail.ParseAddress` rejects leading/trailing/consecutive dots in dot-atom; the regex keeps the ASCII/TLD guard). Alternative (regex-only, as before) re-admits them — rejected per #95 decision A.
- **Decision: hand-rolled dot checks on iOS, not a full RFC parser.** Swift has no `net/mail` equivalent; the client only needs to mirror the three newly-divergent shapes (leading/trailing/consecutive dots in the local part) on top of the existing regex — split on `@`, inspect the local part. Full RFC 5322 parsing client-side would be over-engineering for a pre-submit hint. Alternative (share logic via server pre-check endpoint) adds latency and a new API — rejected.
- **Decision: client/server tests kept in sync by naming the same three vectors.** Both suites use `.a@example.com`, `a.@example.com`, `a..b@example.com` as the canonical reject set plus the same valid-sender fixtures, so divergence shows up as a mirrored failure.
- **Decision: lockout proof is a read-only grep over the users table (expect zero), recorded in the change — not a migration.** Pre-release with no legacy compat burden; if a row ever matched, the decision would need revisiting before shipping strictness.

No new external dependency is introduced (Go stdlib `net/mail`, Go 1.24; Swift `Foundation` regex) — no ctx7 fetch applies; the design relies only on already-implemented stdlib behavior.

## Risks / Trade-offs

- [Risk] `mail.ParseAddress` accepts some quoted/obsolete forms the regex then rejects (or vice versa) — the intersection is intentionally narrower than either alone → Mitigation: tests pin both the reject set and representative valid senders, so any stdlib behavior shift surfaces immediately.
- [Risk] Client mirror drifts from server on future rule changes → Mitigation: mirrored fixture vectors with a comment cross-referencing the server test; server remains authoritative so drift degrades to a post-submit 400, never to a false accept.
- [Risk] Over-strictness rejects a real user's address → Mitigation: lockout grep (expect zero) + pre-release status with no legacy addresses in the wild; RFC dot-atom is the conservative, widely-implemented subset.

## Migration Plan

None — no data migration, no API change, no rollout gating. If the lockout grep finds a matching address, stop and revisit the #95 decision instead of shipping.

## Open Questions

None — decision A (keep-strict + mirror) is recorded in the issue; all unknowns are resolved by the pinned tests.
