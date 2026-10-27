# Contributing to Lifio

This is the human contributor's guide: clone → running app → first PR. AI agents read [`AGENTS.md`](AGENTS.md) instead (short entrypoint pointing at the canonical context); section 3 explains how to drive them.

One rule for every doc edit: **one fact lives in exactly one file — others link.** CI truth lives in [`docs/ci.md`](docs/ci.md), architecture truth in [`docs/project-context.md`](docs/project-context.md), agent rules in `AGENTS.md`. Link those files; never copy their claims here.

## 1. Quickstart

```bash
# Backend (Go 1.24) — from backend/
go build ./...
go test ./... -cover            # SQLite in-memory — no Docker needed
cp .env.example .env            # then fill secrets (see section 2)
openssl rand -hex 32            # generate REFRESH_RECOVERY_KEYS (required — the server fail-fasts without it)
docker-compose up -d postgres
go run ./cmd/server             # serves http://127.0.0.1:8080 (watch stdout for OTP codes with EMAIL_BACKEND=console)
```

```bash
# iOS (Xcode 16+, xcodegen, swiftlint) — from ios/TimeOfLife/
xcodegen generate               # after every project.yml change; never hand-edit the .pbxproj
open TimeOfLife.xcodeproj
swiftlint lint --strict         # --fix autocorrects
xcodebuild -scheme TimeOfLife -destination 'generic/platform=iOS Simulator' build
```

## 2. Environment

- **`.env` keys** (see `backend/.env.example` for the full template): `DATABASE_URL`, `JWT_SECRET` (≥32 bytes), `EMAIL_BACKEND=console` for local dev, `OTP_*`, plus **`REFRESH_RECOVERY_KEYS`** (comma-separated 64-hex AES-256 keys — required at startup) and **`ACCOUNT_STATUS_SECRET`** (≥32 bytes, must differ from `JWT_SECRET` — required at startup). Never commit real credentials.
- **Toolchain pins**: Go 1.24; Xcode 16+; `xcodegen` / `swiftlint` versions pinned in `ios/TimeOfLife/ci_scripts/` (`XCODEGEN_PIN` / `SWIFTLINT_PIN`) — bump code + pins together.
- **`API_BASE_URL`** is per build configuration: Debug → `http://127.0.0.1:8080` (ATS allows plain HTTP only to `127.0.0.1`); Release → `https://timeoflife-api.antonkosenko.pro`. On a physical device, use your LAN IP instead.
- **Signing is per-config**: Debug stays unsigned (simulator/CI need no Apple Developer account); Release signs with team `7923U48U87` and carries the Sign in with Apple entitlement (App ID `com.antonkosenko.timeoflifeapp` needs the SIWA capability; backend needs `APPLE_CLIENT_ID=com.antonkosenko.timeoflifeapp` or `/auth/apple` returns 503).
- Warnings are errors on the app/test targets via `project.yml` — never pass those flags globally (GRDB compiles with `-suppress-warnings`).

## 3. Working with agents

- **Config files**: `opencode.json` defines the agent roles (`explore` = read-only research, `build`/`general` = implement, `plan` = no device access) and model; `AGENTS.md` is their entrypoint; `.opencodereview/rule.json` scopes the AI reviewer; `skills-lock.json` pins agent skills.
- **What to expect**: agents work in an isolated worktree (`timeOfLife.wt/<change>`, one branch per worktree — your checkout stays clean), rebase twice on `origin/main`, and verify with linters + both test suites. Backend and iOS verification run on separate agents in parallel; only one `xcodebuild` runs at a time.
- **Reviews**: comment `/review` on a PR for the advisory stage-1 AI review (never blocking); stage 2 is your self-review against the PR-template checklist. Details: [`docs/review-process.md`](docs/review-process.md).
- **External docs first**: agents must fetch current library/SDK docs via `npx ctx7@latest library` → `docs` before implementing (procedure in `docs/project-context.md`). If a command fails with a quota error, run `npx ctx7@latest login` or set `CONTEXT7_API_KEY` — never let them silently fall back to training data.

## 4. Checks & CI

Mandatory PR checks: `backend.yml` (gofmt, vet, golangci-lint, race tests, coverage floor, OpenAPI contract gate) on `backend/**`; `ios.yml` (xcodegen, SwiftLint, warnings-as-errors build, tests) on `ios/**`; `openspec.yml` (`openspec validate --all --strict`) on every PR. Xcode Cloud is tag-archive-only (TestFlight + signed-dSYM upload). Full guide: [`docs/ci.md`](docs/ci.md).

```bash
cd backend
make lint          # gofmt + vet + golangci-lint (matches CI lint stage)
make test:race     # go test ./... -race (matches CI test step)
```

Fast iOS loop (agent rules + timings): [`docs/ios-test-loop.md`](docs/ios-test-loop.md). Bugfix discipline (reproduce → research → implement → re-verify): [`docs/bugfix-process.md`](docs/bugfix-process.md).

## 5. Manual testing

Unit tests can't cover the Apple sheet, JWKS verification, or the Dynamic Island — verify on a **real device** before releases touching auth or Live Activities: [`docs/manual-testing.md`](docs/manual-testing.md) (Sign in with Apple ×10, Live Activities ×7).

## 6. Releases & deploys

- **TestFlight**: cut via the manual `release` workflow (Actions → `release` → Run workflow, `version` = `X.Y.Z` — strictly greater than current on `main`); it bumps `project.yml` + mirrors every Release `Info.plist`, commits, and pushes tag `vX.Y.Z`. The tag triggers the Xcode Cloud archive → TestFlight upload; the `release.yml verify` job runs `ios.yml` on the pushed head. Do not distribute until both are green. **Adding an Xcode target?** Wire it into `release.yml` (`RELEASE_PLISTS`) + `ios.yml` scheme coverage in the same PR — checklist: `docs/ci.md` → "New-target checklist".
- **Backend**: every `main` push touching `backend/` lints, tests, builds, and deploys to the GCE VM automatically (manual: dispatch the `backend` workflow). System of record is Supabase Postgres (session pooler); `DATABASE_URL` selects it. **Never reboot the VM casually** — the original GCE startup-script rewrote deploy-managed files on boot; post-boot, re-run the `backend` workflow and verify `/health`. Backups: weekly `pg_dump`, 30-day retention, ~350 MB guard on the 500 MB tripwire. Full topology: `docs/project-context.md` → "Deployment".
- **Account deletion rollout** has its own gates (secrets, Apple notification registration, backup-restore restrictions, signed-device checks): [`docs/account-deletion-operations.md`](docs/account-deletion-operations.md). Passing fixture tests do not authorize publishing the new privacy claims ahead of the matching app/backend.
