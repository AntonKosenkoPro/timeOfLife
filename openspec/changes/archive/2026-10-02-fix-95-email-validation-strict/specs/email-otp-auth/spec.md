## Purpose

Pins the canonical email-identifier rule for the passwordless email-OTP path: the exact server-side acceptance shape, its client-side mirror for instant feedback, and the lockout-free precondition for keeping the rule strict.

## ADDED Requirements

### Requirement: Canonical server email rule

The server SHALL accept an OTP-request email only when it satisfies all of: total length ≤ 254 characters; a parseable RFC 5322 address structure whose parsed address equals the input byte-for-byte; and an ASCII mailbox with a dotted domain carrying a 2+ letter top-level domain. In particular the server SHALL reject a local part with a leading dot, a trailing dot, or consecutive dots (e.g. `.a@example.com`, `a.@example.com`, `a..b@example.com`) with 400, while representative valid senders (including `+`-tagged and dotted local parts such as `user+tag@example.com` and `first.last@example.com`) continue to be accepted. The OTP path SHALL remain enumeration-closed: a well-formed request always returns 202 regardless of whether an account exists.

#### Scenario: Dot-edge inputs rejected

- **WHEN** an OTP request carries `.a@example.com`, `a..b@example.com`, or `a.@example.com`
- **THEN** the server responds 400 and no OTP is issued or sent

#### Scenario: Valid senders unchanged

- **WHEN** an OTP request carries a representative valid sender such as `user@example.com`, `user+tag@example.com`, or `first.last@example.com`
- **THEN** the request is accepted (202) and the OTP flow proceeds as before

#### Scenario: Overlong input rejected

- **WHEN** an OTP request carries an otherwise well-formed address longer than 254 characters
- **THEN** the server responds 400

### Requirement: Client mirrors the dot rules for instant feedback

The iOS email validator SHALL reject the same three dot-edge shapes — leading, trailing, and consecutive dots in the local part — so the user gets instant inline feedback instead of a post-submit server rejection. The server remains authoritative: any shape the client accepts but the server rejects SHALL still surface as the existing unified invalid-email message, whose text is unchanged.

#### Scenario: Dot-edge caught before submit

- **WHEN** the user types `.a@example.com`, `a.@example.com`, or `a..b@example.com` in the email field
- **THEN** the client marks the email invalid inline (unified message) without a network request

#### Scenario: Client and server agree on valid senders

- **WHEN** the user types a representative valid sender such as `user+tag@example.com`
- **THEN** the client accepts it and the server accepts it on submit

### Requirement: No pre-existing dot-edge accounts locked out

Keeping this strict rule SHALL be conditional on proof that no existing account holds a dot-edge address: a lookup over the users table for local parts with a leading dot, trailing dot, or consecutive dots SHALL return zero rows (recorded at implementation time; pre-release, so an empty table trivially satisfies this).

#### Scenario: Lockout check passes

- **WHEN** the users table is scanned for dot-edge local parts during implementation
- **THEN** zero matching addresses are found and the strict rule ships as specified
