## Context

See `proposal.md` (Why). Current state: `corsMiddleware` (`backend/internal/server/server.go:237-257`, wired at :151) reflects any `Origin` with `Allow-Credentials:true`; missing-Origin `*` without credentials was already fixed. `TestCORSHeaders` (`server_test.go:133`) pins the echo (localhost:3000 → header present). Config precedent: `TRUSTED_PROXIES` CSV parse at `config.go:184-186` (empty = trust nobody). Auth is Bearer, no web client exists, iOS ignores CORS — so the fix is hardening, not incident response.

## Goals / Non-Goals

**Goals:**
- Non-allowlisted origins are never reflected; `ACAC:true` is never paired with a wildcard or a non-allowlisted reflection.
- Empty default denies; localhost works only via explicit env listing; `PUT` removed from advertised methods.

**Non-Goals:**
- No cookie/CSRF work; no per-route CORS; no frontend origin onboarding beyond the env var.

## Decisions

- **Env allowlist `CORS_ALLOWED_ORIGINS` (CSV, exact match, trimmed), mirroring `TRUSTED_PROXIES`.** Exact string match on the full origin (`scheme://host[:port]`); no regex/subdomain wildcards. Alternatives considered: (a) wildcard/subdomain matching — rejected, over-broad for a relay with no web client; (b) build-tag dev exception — rejected per decision, env-gating keeps prod/dev behavior reviewable in config.
- **Empty default = deny (no echo, no credentials).** Missing `Origin` gets methods/headers advertisement only, never `ACAC:true`. This keeps `curl`/native callers working while browsers get no access.
- **Match → echo + `Allow-Credentials:true` + `Vary: Origin`; else no CORS origin/credentials headers.** `Vary: Origin` prevents cache poisoning of echoed values. `OPTIONS` still returns `204` in all cases (preflight status is not the enforcement point — absent headers enforce).
- **Trim `PUT` from `Allow-Methods`; keep `Content-Type, Authorization`.** The API surface is GET/POST/PATCH/DELETE/OPTIONS; advertising `PUT` invites confusion with no handler behind it.

## Risks / Trade-offs

- [Risk] Exact-match trips on trailing slash / case variants in env config → Mitigation: trim whitespace/empty entries on parse; document the exact `scheme://host[:port]` shape in `.env.example`; tests pin exact-match semantics.
- [Risk] Misconfigured prod allowlist breaks a future web client → Mitigation: deny is fail-closed and observable (missing headers, not 500s); adding the origin is a config-only change.
- [Risk] `Vary: Origin` cache fragmentation → Accepted: correctness over cache efficiency; traffic is authenticated API calls, not CDN cacheables.

## Migration Plan

Config-only rollout: set `CORS_ALLOWED_ORIGINS` where a browser client exists; otherwise leave empty (deny). No DB migration. Rollback is unsetting the var or reverting the middleware — both fail closed. Update `TestCORSHeaders` in the same change so CI pins the new contract.

## Open Questions

None.
