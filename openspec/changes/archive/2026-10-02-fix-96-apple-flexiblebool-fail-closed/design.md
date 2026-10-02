## Context

See proposal.md (Why) for motivation. Current state: `flexibleBool.UnmarshalJSON` in `backend/internal/apple/verifier.go:45-57` already fails closed (unknown shapes → error → `Verify` returns `ErrInvalidToken` → `AppleSignIn` answers 401 `invalid_apple_token`); the spec delta in `specs/apple-signin/spec.md` pins this plus the fact that the parsed value is currently unused (`AppleSignIn` in `handlers/auth.go:410-464` issues `emailVerified=true` unconditionally). Constraints from `docs/project-context.md`: OpenAPI is the authoritative contract (S10 — unchanged); no passwords/secrets involved (R1).

## Goals / Non-Goals

**Goals:**

- Pin the already-fail-closed parsing with regression tests so a future "be lenient" refactor can't silently downgrade unknown shapes to false.
- Record the availability-vs-trust distinction in a test comment so future readers don't misread the stakes.

**Non-Goals:**

- No handler change; no change to RS256/iss/aud/exp/30s-leeway/sub validation, 503 gating, or rate limiting; no iOS change. (This design exists only because `tasks` requires the `design` dependency; there is no implementation approach to choose — the work is tests + a comment.)

## Decisions

- **Decision: pin with unit tests at the `UnmarshalJSON` level plus one handler-level 401 test, no production code change.** The behavior is already correct; the risk is regression, and tests are the cheapest durable pin. Alternative (refactor the handler to consume `IsEmailVerified()`) would change trust semantics — explicitly out of scope.
- **Decision: garbage vectors are `"yes"`, `2`, and `{}`.** They cover the three JSON kinds an unknown shape can take (string, number, object) beyond the accepted `"true"`/`"false"`/`"1"`/`"0"` strings. Alternative (exhaustive fuzzing) is disproportionate for a pinned enum-like set.
- **Decision: the availability-vs-trust note lives as a test comment, not a spec requirement.** It explains intent to future implementers; the normative contract (garbage → 401) is in the spec delta.

No new external dependency is introduced (already-implemented `golang-jwt` + `keyfunc` path) — no ctx7 fetch applies.

## Risks / Trade-offs

- [Risk] Apple adds a new legitimate `email_verified` wire shape that we now reject → Mitigation: fail-closed is the chosen posture per #96 decision A; the 401 + warn log makes the rejection visible, and adding the shape later is a deliberate, tested change.
- [Risk] Test-only change looks like a no-op in review → Mitigation: the spec delta + test comment carry the decision record; validation pins the behavior either way.

## Migration Plan

None — no behavior change, no rollout.

## Open Questions

None.
