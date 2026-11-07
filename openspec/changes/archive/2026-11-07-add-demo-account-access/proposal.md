## Why

App Review cannot depend on accessing the dedicated Gmail inbox: new-IP SMS and two-factor challenges prevent unattended reviewer sign-in. Lifio needs dependable access to its existing synthetic-data account without sharing mailbox credentials or weakening ordinary users' authentication.

## What Changes

- Add an explicitly enabled, server-only reusable six-digit review code through the existing email/code screens and `otp/request` / `otp/verify` endpoints. “Permanent” means no automatic expiry or consumption, not irrevocable access.
- Bind the exception to one existing verified email account's immutable UUID **and** canonical email. Initial intended account: `antonkosenko.appreview@gmail.com`, UUID `b2ea21ec-6b4b-4da7-8668-a3a598a59711`; confirm this binding privately before activation. No credentials are included in these artifacts.
- Suppress OTP generation and email delivery for the configured review address while enabled; preserve the enumeration-closed 202 response and ordinary behavior for every other address.
- Require a keyed verifier, persistent atomic account-wide attempt budgets, existing IP limits, safe telemetry, and explicit enable/rotate/disable procedures. Requests and resends cannot reset protection.
- Issue ordinary device-bound sessions and retain ordinary authorization, synchronization, account deletion, and local-file lifecycle. Never grant privileged access or a different feature experience.
- Document the narrow exception to ordinary passwordless semantics: this reusable short secret is password-like and does **not** prove current mailbox possession. Ordinary users remain passwordless; no password registration/reset system is introduced.

Non-goals: app/iOS UI changes, a public demo button, anonymous/offline authentication, new endpoints, a mailbox/OTP portal, automatic sample-data reset or seeding, deletion exemptions, Apple sign-in changes, generic authentication redesign, and device quota/picker implementation (#46 remains a pre-release blocker).

## Capabilities

### New Capabilities

- `demo-account-access`: Exact-account reusable review-code authentication, protected verification and durable throttling, normal sessions/lifecycle, and private operational controls.

### Modified Capabilities

- `email-otp-auth`: Preserve canonical validation and always-202 requests while explicitly exempting the enabled review address from ordinary OTP issuance/delivery.

## Impact

- Backend: auth/config wiring, dedicated verification helper, transactional Postgres/SQLite attempt storage with additive migration and deletion cleanup, deployment-secret propagation, and regression/contract tests. No external service or new dependency is planned.
- API: unchanged paths, request/response shapes, device header, and existing error vocabulary; authoritative `backend/api/openapi.yaml` must document the review-only semantics and 429 behavior.
- iOS: no production-source, localization, or design changes expected; verify the current six-digit field, resend flow, error mapping, and normal account-bound sign-in against a local backend.
- Docs/requirements at implementation: auth FURPS F1/F3/U5 plus a review-access row; Common R1 secure-storage clarification; `AGENTS.md`/`openspec/config.yaml` passwordless wording narrowed via a durable-context pointer; auth context, README, private-credential-free ops runbook, and manual smoke checklist. Baselines remain untouched until normal sync/archive.
- Existing active changes (CI migration, review-model routing, landing page) do not own this behavior. No production activation, secret generation, data mutation, commit, or deployment is authorized by this planning change.

Research (2026-11-06): Context7 `/websites/developer_apple_app-store_review`, query “Provide a working demo account authentication code in App Review Notes credentials must not expire before review” (current unversioned Apple policy, no SDK pin). Apple requires dependable demo access, not this particular implementation. Direct primary-source checks: [Apple review access](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/), [Authgear's account-specific fixed-code pattern](https://docs.authgear.com/faq-for-authentication/passwordless-demo-user-for-apple-app-review), and [OWASP OTP handling](https://cheatsheetseries.owasp.org/cheatsheets/Multifactor_Authentication_Cheat_Sheet.html#one-time-password-otp-handling-and-storage). HIG and Apple SDK/API research are N/A: existing screens and wire shapes are unchanged; this is backend-only behavior. Library/setup research is deferred to apply for the selected DB/crypto primitives; no new dependency or service is selected here. See design for threats, controls, and re-confirmation gates.
