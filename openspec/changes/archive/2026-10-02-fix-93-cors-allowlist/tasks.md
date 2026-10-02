## 1. Config + template

- [x] 1.1 Parse `CORS_ALLOWED_ORIGINS` (CSV, trimmed, empty entries ignored; empty default = deny) in `backend/internal/config/config.go`, mirroring `TRUSTED_PROXIES` style
- [x] 1.2 Document `CORS_ALLOWED_ORIGINS` in `backend/.env.example` (exact `scheme://host[:port]` shape, empty-default-deny, localhost via explicit listing)

## 2. Middleware hardening

- [x] 2.1 Match → echo `Origin` + `Access-Control-Allow-Credentials: true` + `Vary: Origin`; non-match/missing → no origin/credentials headers (never `ACAC:true` with wildcard/reflected origin)
- [x] 2.2 Trim `PUT` from `Access-Control-Allow-Methods` (keep `GET, POST, PATCH, DELETE, OPTIONS`); keep `Content-Type, Authorization` headers; preserve `OPTIONS 204` in all cases

## 3. Tests + verify

- [x] 3.1 Update `TestCORSHeaders` and add cases: allowlisted origin echoed (+credentials+`Vary`), non-allowlisted origin gets no CORS headers, missing origin gets no credentials
- [x] 3.2 Verify: `gofmt -l .` empty, `go vet ./...`, `go test ./... -cover` green; confirm acceptance (non-allowlisted never reflected; no `ACAC:true` with wildcard/reflection)
