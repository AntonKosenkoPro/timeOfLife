## 1. Pin fail-closed parsing

- [x] 1.1 Add `flexibleBool` unit tests asserting garbage shapes (`"yes"`, `2`, `{}`) return an error (with a comment noting `AppleSignIn` currently issues `emailVerified=true` regardless, so today's stakes are availability, not trust escalation)
- [x] 1.2 Add unit tests asserting all known wire shapes are unchanged (`true`/`"true"`/`1` → true; `false`/`"false"`/`0`/null → false)
- [x] 1.3 Add a handler-level test asserting a token with a garbage `email_verified` shape → 401 `invalid_apple_token`

## 2. Verify

- [x] 2.1 Run `go test ./...` (incl. `internal/contract` gate) and confirm green
- [x] 2.2 Run `gofmt -l .`, `go vet ./...`, `golangci-lint run` and confirm clean
- [x] 2.3 Confirm no `handlers/auth.go`, OpenAPI, FURPS, or iOS changes were needed (tests-only change)
