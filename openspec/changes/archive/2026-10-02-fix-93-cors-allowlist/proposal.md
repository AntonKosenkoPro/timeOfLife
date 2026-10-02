## Why

`corsMiddleware` (`backend/internal/server/server.go:237-257`, wired at :151 for all routes) reflects any presented `Origin` with `Access-Control-Allow-Credentials: true`. Auth is Bearer (not cookies) and no web client exists (iOS native ignores CORS), so exploitability is low — but any website can still make credentialed calls from a victim's browser. GitHub issue #93.

## What Changes

- **Env allowlist `CORS_ALLOWED_ORIGINS`** (CSV, mirrors `TRUSTED_PROXIES` style in `backend/internal/config/config.go:184-186`): exact-match against the request `Origin`. Empty default = deny (no echo, no credentials; iOS native unaffected).
- **Localhost dev exception:** explicit dev list, env-gated (not build-tag) — localhost origins are allowed only when explicitly listed.
- **Trim `PUT` from allowed methods** (API uses GET/POST/PATCH/DELETE/OPTIONS only); keep `Content-Type, Authorization` headers, `OPTIONS 204` preflight, and `Vary: Origin` on allowlisted echoes.
- **Tests + template:** update `server_test.go:133 TestCORSHeaders` (pins current echo) to allowlisted / non-allowlisted / missing-origin cases; add `.env.example` entry.
- Explicitly **out of scope**: cookie-based auth, CSRF tokens, per-route CORS policies, frontend origins beyond the allowlist.

## Capabilities

### New Capabilities

- `relay-cors`: CORS allowlist contract for the relay — which origins are echoed (with credentials) vs denied, default-deny, dev exception, methods/headers, preflight handling.

### Modified Capabilities

None — no existing baseline spec covers CORS.

## Impact

- Code: `backend/internal/config/config.go` (parse `CORS_ALLOWED_ORIGINS`), `backend/internal/server/server.go` (match→echo+credentials+`Vary` else no CORS headers), `backend/.env.example`, `backend/internal/server/server_test.go`.
- APIs: browsers calling from non-allowlisted origins no longer receive `Access-Control-Allow-Origin` / `Allow-Credentials`; native iOS (no CORS) and `curl`/missing-Origin callers are unaffected except they never get `ACAC:true` with a wildcard/reflected origin.
- Tests: `go test ./...` green; new CORS cases fail before the fix (echo-all) and pass after.
