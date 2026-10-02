## 1. Server tests (pin strict rule)

- [x] 1.1 Add handler-level tests asserting `.a@example.com`, `a..b@example.com`, `a.@example.com` → 400 with no OTP issued
- [x] 1.2 Add handler-level tests asserting representative valid senders (`user@example.com`, `user+tag@example.com`, `first.last@example.com`) are still accepted
- [x] 1.3 Run `go test ./...` for the auth package and confirm green

## 2. iOS client mirror

- [x] 2.1 Extend `AuthValidator.isValidEmail` with hand-rolled local-part dot checks (reject leading / trailing / consecutive dots), keeping the existing regex for the rest
- [x] 2.2 Add `AuthValidator` tests mirroring the server vectors (three dot-edge rejects + valid-sender accepts, kept in sync by fixture naming)
- [x] 2.3 Run `swiftlint lint --strict` and the iOS test suite; confirm the unified U4 message text is unchanged (no new strings)

## 3. Docs and lockout proof

- [x] 3.1 Add the canonical-rule one-liner to FURPS Sign-up U1 (RFC dot-atom local part, ≤ 254 chars)
- [x] 3.2 Run the lockout proof lookup over the users table for dot-edge local parts, record the zero-row result in the change
- [x] 3.3 Re-check FURPS Sign-up U1/U4 rows and confirm `backend/api/openapi.yaml` needs no change (`format: email`, `maxLength: 254` already pin the contract)
- [x] 3.4 Run `gofmt -l .`, `go vet ./...`, backend + iOS suites green per S5

## Lockout proof (3.2 record)

Read-only grep over every users-table write path, 2026-10-02: the `users` table is written only by `UpsertUser` (OTP-request path, gated by `validateEmail` — dot-edge already 400) and `UpsertUserByAppleSubject` (Apple relay/private emails); migrations contain zero `INSERT INTO users` seeds. A scan of all quoted email-like literals in `backend/internal` finds exactly one dot-edge hit — the `validateEmail` code comment citing `.a@example.com` / `a..b@example.com` — and no fixture, seed, or stored address with a leading/trailing/consecutive-dot local part (`"@"` / `"***@"` hits are `maskEmail` implementation fragments, not addresses). Result: zero dot-edge addresses — strict rule ships as specified.
