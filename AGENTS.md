# AGENTS.md

Agent entrypoint for this repo. **Read [`docs/project-context.md`](docs/project-context.md) first** — it holds the durable, accurate architecture and context (S7). This file only orients you and enforces the non-negotiables; it is deliberately short.

## What this is

**Time of Life** — a personal time-tracking iOS app (SwiftUI, iOS 15+, local-first) with a Go backend that acts as an **optional sync relay**. Current scope: auth MVP (passwordless email-OTP + Sign in with Apple) and the Track experience (three-tab shell, numeric timer, Activity search + quick-create, Refine, Profile, compact cross-tab timer).

## OpenSpec routing (read this before touching behavior)

The repo is spec-driven (`openspec/config.yaml`, `schema: spec-driven`). See `openspec/README.md` for the workflow; the essentials:

- **Baseline specs** (`openspec/specs/<capability>/spec.md`): current contract (`app-shell`, `timer-capture-experience`). Never edit directly — behavior changes go through a change.
- **Active deltas**: `openspec/changes/local-first-sync-architecture/` — the local-first contract (delta specs `local-first-store`, `sync-client`, `entry-provenance`, `lock-screen-controls`; decisions D1–D10 in `design.md`). Check its `tasks.md` and `openspec status --change local-first-sync-architecture` before implementing; mark tasks as you complete them.
- **Archives** (`openspec/changes/archive/`): history (e.g. `redesign-track-experience`); their deltas are already folded into the baselines.

## Non-negotiables

- **LocalStore is the single mutation chokepoint** (GRDB in App Group `group.com.antonkosenko.timeoflife`) — no raw GRDB writes outside it.
- **Incomplete UI surfaces — do not claim they are done**: UndoToast/shake-to-undo, the "Enable Sync" `AuthFlowView` sheet presentation (Profile currently does a silent `restoreSession()`), "via <Source>" labels, and the iOS 18 lock-screen ControlWidget (no target in `project.yml` yet). Full list: `docs/project-context.md` → "Incomplete / deferred", mirroring open tasks in `local-first-sync-architecture/tasks.md`.
- **OpenAPI is the authoritative API contract** (`backend/api/openapi.yaml`, S10). Endpoint changes update both sides + the spec.
- **No backward compat for on-disk formats** (pre-release): edit `Codable` shapes in place, no legacy branches.
- **No passwords, no plaintext secrets** (R1); tokens in Keychain only; user-enumeration closed (`otp/request` always 202).
- **iOS strings** go to both `en.lproj` and `ru.lproj` + `L10n` (U4).
- **XcodeGen-managed** — edit `project.yml`, run `xcodegen generate`; never hand-edit the `.pbxproj`.
- **SwiftUI views use `Theme` semantic colors only**; no raw `Color` literals.

## Repo layout (short)

```
backend/                 Go (chi + pgx/Postgres; sqlite for tests) — relay: auth + activities/categories/entries
ios/TimeOfLife/          SwiftUI app (iOS 15+), XcodeGen-managed
  TimeOfLife/Features/{Auth,AppShell,TimeTracking,Catalog,Sync,AppleSignIn}
  TimeOfLife/Core/Storage/   LocalStore.swift (GRDB), UndoBufferStore.swift, SessionCache.swift
  TimeOfLife/Core/           networking, keychain, reachability, theme, navigation, DI, components
docs/                    project-context.md (canonical context), ci.md
openspec/                specs + changes (see above)
Requirements/FURPS/      FURPS+ table (Common.md, Timetracking.md, Sign-up_and_Sign-in.md, Activity_Catalog_and_Categories.md)
Design/                  text design system — see Design/README.md
.github/workflows/       backend.yml + ios.yml (mandatory PR checks)
```

## Build, test, run

### Backend (Go 1.24) — from `backend/`
```bash
go build ./...
go test ./... -cover            # tests use SQLite — no Docker needed
golangci-lint run && gofmt -l . && go vet ./...
docker-compose up -d postgres && cp .env.example .env && go run ./cmd/server
```

### iOS (Xcode 16+, xcodegen, swiftlint) — from `ios/TimeOfLife/`
```bash
xcodegen generate
swiftlint lint --strict         # --fix autocorrects
xcodebuild -scheme TimeOfLife -destination 'generic/platform=iOS Simulator' build
```

## Required on every iteration (S5)

1. Linters + build green; app/test target warnings are errors via `project.yml`; `gofmt -l .` empty.
2. Both test suites green (`go test ./...`; `xcodebuild test -scheme TimeOfLife -destination '<available simulator>'`).
3. Re-check the relevant `Requirements/FURPS/*.md` rows; fix conflicts.
4. Update docs if architecture/contract/run steps or visual design changed: `docs/project-context.md`, `README.md`, `openspec/` artifacts + `openspec/config.yaml` guidance, relevant `Design/*.md`, `backend/api/openapi.yaml`. Keep `AGENTS.md` short — point to `docs/project-context.md`.
5. Prefer existing utilities; remove dead code.

## Flow recommendations

- Plan every not obvious task (that will consume over 100k tokens per session)
- Use subagents whenever it's suitable
- Ask the user to start a new session if the current context overwhelms 200k tokens
