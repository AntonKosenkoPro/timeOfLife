# App Review Access (demo-account-access) — operator runbook

This runbook is the single operational reference for Lifio's App Review
exception: one synthetic-data account reachable through the ordinary
email/code screens with a reusable server-side code. **The feature ships
disabled** (`REVIEW_ACCESS_ENABLED` unset/false) and stays disabled until the
owner completes the private activation checklist below. No production code,
credential, email, or account data appears in this file or anywhere in the
repository — generation and placement are always private.

## What reviewers experience

- The normal sign-in flow: enter the review email on the email screen, enter
  the six-digit code on the code screen. No Gmail inbox, no second device, no
  demo button, no special build.
- The code is reusable: no expiry, no single-use consumption, no prerequisite
  request. Resends return the ordinary 202, send no email, and change nothing.
- Sessions are ordinary device-bound sessions: per-device refresh families,
  15-minute access TTL, independent logout, normal sync/ownership. Reviewers
  can edit and permanently delete the shared account like any other account.

## Eligibility (exact binding, no exceptions)

When enabled, authentication requires ALL of the following for the configured
address — otherwise it fails with the ordinary `invalid_otp` and issues
nothing:

- The account with the configured immutable UUID exists at the configured
  canonical email (byte-exact; aliases never match). Both identifiers must
  be canonical lowercase — uppercase values fail startup instead of silently
  never matching.
- The account is verified and email-created (no Apple identity, never
  upserted or verified by this path).
- The submitted code verifies against the keyed verifier (HMAC-SHA256 over
  purpose/version, UUID, canonical email, code with the dedicated 32-byte
  key, constant-time compare).
- An account-wide attempt budget has capacity: at most **5 evaluations per
  rolling 15 minutes** AND **20 per rolling 24 hours**, enforced atomically
  in the database (reserve-before-compare). Denied evaluations consume
  nothing and extend nothing; success never resets the budgets. Exhaustion
  returns `429 rate_limited` with a `Retry-After` header (seconds until both
  windows have capacity).
- The existing per-IP verification limit still applies in front.

A database-only disclosure (without the dedicated key) provides no offline
guessing oracle: the table holds only timestamps, and the verifier is keyed.

## Private credential lifecycle

All generation happens on the operator machine with approved private tooling.
Nothing here is a real credential — every value below is a placeholder shape.

### 1. Choose the binding (before activation)

- Confirm privately: the exact lowercase UUID and canonical lowercase email
  of the existing verified email-created synthetic-data account, and that its content is
  synthetic and safe to share/mutate. No production or personal data.
- Confirm the account's email provider state needs nothing (reviewers never
  touch the mailbox).

### 2. Generate the code and key (private)

- Choose a uniformly random six-digit code with approved private tooling
  (password manager generator). No predictable or example code.
- Generate a dedicated 32-byte key: `openssl rand -hex 32` (64 hex chars).
  The key is independent of JWT, refresh-recovery, account-status, and Apple
  secrets; keep it in the password manager alongside the code.

### 3. Compute the verifier (private)

From the repo root, with `REVIEW_CODE_KEY` in the environment (never argv):

```bash
cd backend
printf '%s' "$REVIEW_CODE_KEY" >/dev/null # sanity: set, not printed
REVIEW_CODE_KEY="$REVIEW_CODE_KEY" go run ./cmd/review-access verifier \
  --account-id <REVIEW_ACCOUNT_UUID> \
  --email <review-canonical-email> \
  --out /private/secure/path/review_code_verifier.hex
```

Type the code at the stdin prompt (it is never echoed). The verifier hex is
written only to the protected `--out` file (created 0600). Verify the file
is 64 hex chars, then place the four values into deployment secrets:

- `REVIEW_ACCOUNT_ID`, `REVIEW_ACCOUNT_EMAIL` (identifiers — still secrets,
  never logged),
- `REVIEW_CODE_VERIFIER` (file content),
- `REVIEW_CODE_KEY` (the dedicated key),
- and set the `REVIEW_ACCESS_ENABLED` variable to `true`.

### 4. Enable fleet-wide

- Deploy so **every** serving backend instance carries the enabled binding.
  A stale disabled instance still serves ordinary OTP for the address; a
  stale enabled instance after disablement would still accept the old code.
  Never represent the change as complete until the whole fleet is on it.
- Smoke the normal app screens against the deployment with a synthetic check
  (separate devices/networks within budgets): two logins (including one past
  ordinary OTP TTL), one resend, one wrong code, two-device session check.
- Only after the smoke passes, update the private Review Notes (template
  below) and submit.

### 5. Rotate the code/key

- Generate a new code and/or key privately, recompute the verifier, update
  all deployment secrets, and redeploy fleet-wide.
- Rotation takes effect on deployment: the old code stops authenticating via
  the exception. Attempt history is intentionally NOT cleared.
- After the fleet converges, revoke the review account's refresh/recovery
  credentials (next section) so pre-rotation sessions cannot linger.

### 6. Revoke sessions (no data loss)

With `DATABASE_URL` pointing at the deployment database:

```bash
cd backend
DATABASE_URL='<deploy-dsn>' go run ./cmd/review-access revoke \
  --account-id <REVIEW_ACCOUNT_UUID> \
  --confirm-account-id <REVIEW_ACCOUNT_UUID>
```

Both flags must carry the same UUID (explicit confirmation). The command
reuses the atomic `RevokeAllUserSessions` primitive: refresh tokens and
pending recovery receipts die together. It deletes no data and clears no
attempt history. Existing access JWTs remain usable only until their
ordinary expiry (at most 15 minutes) — no immediate access-token kill switch
is claimed. Re-verify afterwards: the next refresh must fail, and in-flight
issuance may need one repeat verification after quiescence.

### 7. Disable

- Set `REVIEW_ACCESS_ENABLED=false` (or empty) fleet-wide and redeploy. The
  reusable-code route closes; the address restores ordinary mailed OTP.
- Revoke the review account's sessions as above.
- Rotating the dedicated key/verifier after disablement is defense in depth,
  not required.

### 8. Deletion / replacement recovery

- Reviewers can delete the shared account through the normal Delete path.
  Deletion atomically purges content, credentials, AND review-attempt rows;
  the configured code then cannot recreate or access anything (request stays
  202, verify stays `invalid_otp`).
- Recovery is explicit and owner-side: re-provision synthetic content and —
  if the replacement carries a new UUID — update `REVIEW_ACCOUNT_ID`
  fleet-wide. The exception never silently rebinds; a same-email new UUID
  inherits nothing.

## Review Notes template (private App Store Connect field)

```text
Sign in with the email address below on the normal login screens — no mailbox
access needed.

Email: <review-canonical-email>
Code: <six-digit-code> (reusable; resends change nothing)

The account holds shared synthetic demo data; reviewers may edit or delete
anything. If the account is deleted, sign-in stops working until we
re-provision — contact us via Resolution Center and we will restore access
promptly. Access stays enabled for the whole review period including
follow-ups.
```

Keep Gmail access out of the notes entirely: reviewers must never depend on
the dedicated mailbox (new-IP SMS/two-factor challenges block unattended
sign-in there).

## Monitoring and availability

- Watch the bounded `review auth outcome` diagnostics (`success`, `invalid`,
  `throttled`, `unavailable`, binding mismatch) — outcome metadata only,
  never identifiers, codes, keys, tokens, emails, or bodies. Investigate
  `throttled` spikes (someone may be guessing) and any `unavailable`
  (budget store failure fails closed to a service error).
- Before submission and during review: confirm the binding is enabled
  fleet-wide, budgets have headroom, and the owner is reachable to restore
  the account if reviewers delete it. Never stop the deployment mid-review
  without completing disablement everywhere.
- Rollback is config-only plus redeploy: disable everywhere, revoke review
  sessions, then redeploy the previous pinned image if needed. The additive
  `review_auth_attempts` table stays in place — older code ignores it and
  keeps serving ordinary email OTP. Never delete review content as rollback.

## What this is NOT

- Not a password system: this reusable short secret is password-like and
  does NOT prove current mailbox possession. Ordinary users stay
  passwordless; no password registration/reset exists.
- Not stronger than it looks: ~20 bits of entropy with strict budgets,
  keyed verification, private distribution, monitoring, and owner-controlled
  rotation/disablement. A combined key+config disclosure permits fast
  enumeration — rotate on any exposure.
- Not a quota bypass: device quota/picker (#46) still gates release
  separately; this change adds no quota exemption.
