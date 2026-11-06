## Purpose

Provide dependable App Review access to one synthetic-data Lifio account using a reusable code, without mailbox access or changes to ordinary account security and lifecycle.

## ADDED Requirements

### Requirement: Explicit exact-account review exception
The server SHALL support at most one configured review account, disabled by default. When enabled, review authentication SHALL require both the configured immutable account UUID and canonical email to identify the same existing, verified, email-created account. Email canonicalization SHALL use the ordinary email path; provider-specific alias, domain, wildcard, or substring matching SHALL NOT select the account. The exception SHALL NOT create accounts, mark unverified accounts verified, select Apple identities, or apply to another UUID that later uses the same email. Incomplete or malformed enabled configuration SHALL fail startup without disclosing verification material.

#### Scenario: Feature disabled by default
- **WHEN** review access is not explicitly enabled
- **THEN** both OTP endpoints follow ordinary behavior and no reusable-code exception is active

#### Scenario: Binding does not match
- **WHEN** enabled review verification resolves a missing, unverified, Apple-created, or different-UUID account at the configured address
- **THEN** authentication fails without issuing credentials, creating an account, or changing verification state

#### Scenario: Another address or alias is used
- **WHEN** the review code is supplied for an address other than the configured canonical email
- **THEN** it grants no review-code authority and that address follows ordinary OTP behavior

### Requirement: Reusable code through ordinary authentication endpoints
For the enabled configured review address, a well-formed `POST /api/v1/auth/otp/request` SHALL return the ordinary 202 response without generating, persisting, or sending an OTP, creating an account, changing the review code, or resetting attempt budgets. `POST /api/v1/auth/otp/verify` SHALL accept the configured six-ASCII-digit code without automatic expiry, single-use consumption, or a prerequisite request. A successful previous use, resend, server restart, or ordinary OTP TTL passing SHALL NOT invalidate it. The server SHALL NOT fall back to a previously emailed OTP for this address while the exception is enabled. The path, bodies, device header, success response, and existing error vocabulary SHALL remain compatible with the shipping iOS client. Review-code rejection SHALL use `401 invalid_otp`; throttling SHALL use `429 rate_limited` with the ordinary error envelope. Existing malformed-body/device-header validation SHALL remain enforced. The fixed code is an explicit password-like exception, not evidence of current mailbox possession.

#### Scenario: Repeated reviewer sign-in
- **WHEN** an eligible reviewer submits the correct code on two devices, within attempt budgets, including after ordinary OTP expiry would have elapsed
- **THEN** both sign-ins succeed using normal device-bound sessions without email access or code rotation

#### Scenario: Resend neither emails nor resets
- **WHEN** the reviewer requests or resends a code for the enabled configured address
- **THEN** the server returns 202, sends no email, and preserves the fixed verifier and all attempt history

#### Scenario: Previously emailed code cannot bypass review controls
- **WHEN** a different ordinary OTP issued before enablement is submitted for the enabled review address
- **THEN** it is not accepted as an alternate authentication route

### Requirement: Protected verification material
The system SHALL retain no plaintext review code in server configuration, databases, source control, application bundles, logs, traces, or metrics. Verification material SHALL be protected with a dedicated high-entropy server secret stored separately from the database and cryptographically bound to the account UUID, canonical email, and review purpose; a database-only disclosure SHALL NOT permit offline enumeration of the six-digit code. Verification SHALL use constant-time comparison. The owner SHALL retain the actual code only in approved private credential storage and Apple's private review information; operational tooling SHALL NOT place it in command-line arguments or log output. No code or key SHALL be included in public examples or repository artifacts.

#### Scenario: Database-only disclosure
- **WHEN** an attacker obtains operational database contents without the dedicated verification key
- **THEN** those contents do not provide a plaintext code or an unkeyed verifier for offline six-digit guessing

#### Scenario: Invalid code produces telemetry
- **WHEN** review authentication fails and emits operational diagnostics
- **THEN** diagnostics contain only bounded outcome metadata, not the submitted code, verifier, key, tokens, email, or request body

### Requirement: Durable atomic account-wide attempt budgets
Review verification SHALL enforce account-wide budgets of at most five evaluated code submissions in any rolling 15 minutes and twenty in any rolling 24 hours, in addition to existing IP-based defenses. Every evaluated submission, correct or incorrect, SHALL consume capacity atomically before code comparison or session issuance; success SHALL NOT reset the budgets. A denied submission SHALL NOT evaluate the code or extend the budget window. IP/device changes, concurrent requests, replicas, restarts, resends, feature toggles, and credential rotation SHALL NOT clear or bypass retained attempt history. Capacity SHALL return as admitted submissions age out. Throttled responses SHALL include `Retry-After` seconds until the next available account-wide capacity. Failure to durably enforce the budget SHALL fail closed with the existing service-error contract and SHALL NOT authenticate.

#### Scenario: Distributed concurrent guessing
- **WHEN** requests from multiple IPs, devices, or server instances compete for the last available submission
- **THEN** at most one is admitted and all others receive `429 rate_limited` without code evaluation

#### Scenario: Restart and resend do not reset protection
- **WHEN** an account has exhausted capacity and the server restarts or the client resends or changes device
- **THEN** the account remains throttled until enough admitted submissions age out

#### Scenario: Long-window and successful-attempt accounting
- **WHEN** twenty submissions have been admitted within 24 hours, including successful ones, and the short window has spare capacity
- **THEN** further review submissions remain throttled by the 24-hour budget without resetting on success or rotation

#### Scenario: Persistent storage unavailable
- **WHEN** the server cannot durably reserve a review attempt
- **THEN** it returns a service error without falling back to in-memory limits, ordinary OTP verification, or successful authentication

### Requirement: Normal account permissions sessions and deletion
A review-code login SHALL issue the normal access, refresh, and account-status credentials under existing device identity, refresh TTL/recovery, logout, ownership, and account-lifecycle rules. It SHALL NOT bypass mandatory sign-in, ordinary account authorization, local account-file binding, account deletion, or current revocation fences. Review credentials SHALL authorize only the configured ordinary account and its data. Reviewers SHALL be able to edit and permanently delete that account through the same functionality as other users. Deletion SHALL atomically remove its persisted review-attempt records with its other operational data; later same-email registration SHALL receive no inherited review exception. Review authentication racing deletion SHALL NOT resurrect or issue a usable session for the deleted UUID.

#### Scenario: Two reviewer devices remain independent
- **WHEN** two devices sign in to the same review account and one signs out
- **THEN** ordinary per-device logout semantics apply and the other device's session remains valid

#### Scenario: Reviewer deletes the account
- **WHEN** the authenticated reviewer confirms permanent account deletion
- **THEN** the ordinary purge removes the account, content, credentials, and persisted attempt records, and the configured review code cannot recreate or access it

#### Scenario: Deleted email is registered again
- **WHEN** ordinary email registration later creates a different UUID using the same address
- **THEN** the previous review code does not authorize that new UUID without explicit operator reconfiguration

### Requirement: Private enablement rotation and shutdown
The owner SHALL be able to enable, rotate, or disable the exception without rebuilding iOS or introducing public management endpoints. Changes SHALL apply across every serving backend instance through a documented deployment procedure; a stale enabled instance SHALL NOT be represented as completed shutdown. Disablement SHALL remove the reusable-code route to new sessions while restoring ordinary email OTP behavior. Rotation SHALL stop accepting the old reusable verifier through the exception. Either action SHALL support explicitly revoking all refresh/recovery credentials for exactly the review UUID. Existing access JWTs SHALL retain only their ordinary remaining lifetime, at most 15 minutes; immediate invalidation SHALL NOT be claimed. The runbook SHALL require synthetic data only, private review instructions, monitoring, an owner availability check before submission, and explicit recovery if reviewers delete the account. It SHALL NOT automatically reset content, exempt deletion, or silently rebind a replacement UUID.

#### Scenario: Code is rotated or disabled
- **WHEN** the owner completes the documented fleet-wide change and review-account refresh/recovery revocation
- **THEN** the old code no longer authenticates via the exception, old refresh/recovery credentials cannot renew sessions, other accounts remain unaffected, and residual access-token lifetime is disclosed

#### Scenario: Submission uses current credentials
- **WHEN** the owner prepares App Review information
- **THEN** the private notes explain the ordinary email/code flow, fixed code, lack of mailbox requirement, shared synthetic account, and account-deletion consequences, and access remains enabled for the intended review period
