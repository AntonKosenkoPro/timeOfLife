## Purpose

Pins the relay's browser CORS contract: which origins receive credentialed echoes vs no CORS headers, so a victim's browser never makes credentialed calls from an attacker origin.

## ADDED Requirements

### Requirement: CORS origin allowlist with default deny

The relay SHALL echo an `Origin` only when it exactly matches an entry in the `CORS_ALLOWED_ORIGINS` allowlist (comma-separated, trimmed; empty entries ignored). An empty/unset allowlist SHALL deny all origins: no `Access-Control-Allow-Origin` echo and no `Access-Control-Allow-Credentials` for any presented `Origin`. A non-allowlisted presented `Origin` SHALL receive no CORS headers. A request with no `Origin` SHALL receive no `Access-Control-Allow-Credentials` (never `ACAC:true` with a wildcard or reflected origin). Localhost development origins are allowed only when explicitly listed in the allowlist (env-gated, never build-tag-gated). iOS native callers (which ignore CORS) SHALL be unaffected.

#### Scenario: Allowlisted origin is echoed with credentials
- **WHEN** a request presents an `Origin` exactly matching a `CORS_ALLOWED_ORIGINS` entry
- **THEN** the response carries `Access-Control-Allow-Origin: <origin>`, `Access-Control-Allow-Credentials: true`, and `Vary: Origin`

#### Scenario: Non-allowlisted origin is not reflected
- **WHEN** a request presents an `Origin` not in the allowlist
- **THEN** the response carries no `Access-Control-Allow-Origin` and no `Access-Control-Allow-Credentials` headers

#### Scenario: Empty allowlist denies all
- **WHEN** `CORS_ALLOWED_ORIGINS` is empty or unset and a request presents any `Origin`
- **THEN** the response carries no CORS origin/credentials headers

#### Scenario: Missing origin never yields credentials
- **WHEN** a request has no `Origin` header
- **THEN** the response never carries `Access-Control-Allow-Credentials: true` (with wildcard or otherwise)

### Requirement: CORS preflight methods and headers

The relay SHALL answer `OPTIONS` preflight with `204` and SHALL advertise allowed methods `GET, POST, PATCH, DELETE, OPTIONS` (no `PUT`) and allowed headers `Content-Type, Authorization`. Preflight CORS origin headers follow the allowlist requirement above: allowlisted origins are echoed with credentials + `Vary: Origin`; non-allowlisted or missing origins get no origin/credentials headers while the methods/headers advertisement and `204` status are preserved.

#### Scenario: Preflight advertises methods without PUT
- **WHEN** a browser sends an `OPTIONS` preflight
- **THEN** the response status is `204` with `Access-Control-Allow-Methods: GET, POST, PATCH, DELETE, OPTIONS` and `Access-Control-Allow-Headers: Content-Type, Authorization`

#### Scenario: Preflight from non-allowlisted origin carries no echo
- **WHEN** an `OPTIONS` preflight presents a non-allowlisted `Origin`
- **THEN** the response is still `204` with the methods/headers advertisement but carries no `Access-Control-Allow-Origin` and no `Access-Control-Allow-Credentials`
