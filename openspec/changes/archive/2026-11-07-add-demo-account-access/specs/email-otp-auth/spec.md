## MODIFIED Requirements

### Requirement: Canonical server email rule

The server SHALL accept an OTP-request email only when it satisfies all of: total length ≤ 254 characters; a parseable RFC 5322 address structure whose parsed address equals the input byte-for-byte; and an ASCII mailbox with a dotted domain carrying a 2+ letter top-level domain. In particular the server SHALL reject a local part with a leading dot, a trailing dot, or consecutive dots (e.g. `.a@example.com`, `a.@example.com`, `a..b@example.com`) with 400, while representative valid senders (including `+`-tagged and dotted local parts such as `user+tag@example.com` and `first.last@example.com`) continue to be accepted. The OTP path SHALL remain enumeration-closed: a well-formed request always returns 202 regardless of whether an account exists. The explicitly enabled review address defined by `demo-account-access` SHALL retain that same validation and 202 response while suppressing ordinary OTP issuance, delivery, and account creation. Outside that narrowly scoped exception, normal OTP generation, expiry, single-use consumption, delivery, and attempt handling SHALL remain unchanged.

#### Scenario: Dot-edge inputs rejected

- **WHEN** an OTP request carries `.a@example.com`, `a..b@example.com`, or `a.@example.com`
- **THEN** the server responds 400 and no OTP is issued or sent

#### Scenario: Valid senders unchanged

- **WHEN** an OTP request carries a representative valid sender such as `user@example.com`, `user+tag@example.com`, or `first.last@example.com` outside the enabled review exception
- **THEN** the request is accepted (202) and the OTP flow proceeds as before

#### Scenario: Overlong input rejected

- **WHEN** an OTP request carries an otherwise well-formed address longer than 254 characters
- **THEN** the server responds 400

#### Scenario: Review address uses the same public response

- **WHEN** a well-formed request carries the configured review address while review access is enabled, including when its expected account is missing or mismatched
- **THEN** the server returns the ordinary 202 response without sending an OTP, creating an identity, or revealing review-account state
