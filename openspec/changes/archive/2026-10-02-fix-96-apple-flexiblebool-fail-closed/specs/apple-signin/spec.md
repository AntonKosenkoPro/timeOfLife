## ADDED Requirements

### Requirement: Unknown email_verified claim shapes fail closed

Verification of an Apple identity token SHALL reject (rather than downgrade) an `email_verified` claim in an unknown shape: only JSON `true` / `"true"` / `1` parse as verified and only JSON `false` / `"false"` / `0` / null parse as unverified — any other shape (e.g. `"yes"`, `2`, `{}`) SHALL fail token verification, and the sign-in endpoint SHALL answer 401 `invalid_apple_token` for such tokens. The parsed value is currently unused by the sign-in handler, which issues sessions as email-verified for all Apple users regardless — so today this strictness governs availability (reject vs. accept the token), not trust escalation; it is future-proofing for when the verified flag gates something.

#### Scenario: Garbage email_verified shape rejected

- **WHEN** an otherwise correctly signed, unexpired Apple identity token carries `email_verified` in an unknown shape such as `"yes"`, `2`, or `{}`
- **THEN** verification fails and the server returns 401 with error code `invalid_apple_token`

#### Scenario: Known wire shapes unchanged

- **WHEN** an otherwise valid Apple identity token carries `email_verified` as `true`, `"true"`, or `1`
- **THEN** verification succeeds and the token parses as verified; when it carries `false`, `"false"`, `0`, or null, verification succeeds and the token parses as unverified
