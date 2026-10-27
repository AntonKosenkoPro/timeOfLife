## Purpose

Backend builds are currently anonymous: the image is always overwritten as `backend:latest` and `/health` reports only `{"status":"ok"}`, so a tester can never say which relay a bug came from. This capability pins every backend release to an immutable image tag and stamps the running server with its tag and commit, mirroring the iOS Profile row — both ends of the system become identifiable from two strings.

## ADDED Requirements

### Requirement: Pinned backend image tags

Every push of a `backend/*` tag SHALL produce an immutable container image tagged with the tag name (e.g. `ghcr.io/<repo>/backend:backend-v2.5.0`) in addition to the floating `backend:latest`. Pushed backend tags SHALL be annotated, signed, owner-only, and never moved — the same tag discipline as iOS namespaces.

#### Scenario: Backend tag produces a pinned image

- **WHEN** the owner pushes signed `backend/v2.5.0`
- **THEN** the backend workflow builds and pushes both `backend:backend-v2.5.0` (immutable) and `backend:latest` (floating pointer)

#### Scenario: Rollback redeploys a pinned image

- **WHEN** `backend-v2.5.0` is found bad in production
- **THEN** recovery redeploys `backend-v2.4.0` by tag — never by rebuilding old source or trusting `:latest`

### Requirement: Health endpoint reports build identity

`GET /health` SHALL report the running server's release identity alongside status: `{"status":"ok","version":"<tag>","sha":"<7-char-SHA>"}`. Both fields are stamped at image build time (tag + commit SHA via build args); when unavailable (local `go run`, missing build args) they SHALL fall back to `"?"` without changing the `200` status or the `status` field. The response shape stays backward-compatible: existing `status`-only readers keep working.

#### Scenario: Staging answers with its identity

- **WHEN** a client calls `GET /health` on a tagged deployment
- **THEN** it receives `200` with `{"status":"ok","version":"backend/v2.5.0","sha":"a1b2c3d"}`

#### Scenario: Local dev falls back gracefully

- **WHEN** the server runs unstamped (local `go run ./cmd/server`)
- **THEN** `/health` returns `200` with `"version":"?"` and `"sha":"?"`
