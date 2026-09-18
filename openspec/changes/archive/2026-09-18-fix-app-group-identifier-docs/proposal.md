## Why

The shipped code stores the local database in App Group `group.com.antonkosenko.timeoflifeapp` (entitlement + `LocalStore.appGroupID` agree, app verified working), but four planning/doc surfaces still cite the shorter `group.com.antonkosenko.timeoflife` — a leftover from the `local-first-sync-architecture` draft that never matched the implementation. Anyone provisioning a widget, Screen Time extension, or Control intent from the docs would request the wrong container and silently read an empty database.

## What Changes

- Correct the App Group string to `group.com.antonkosenko.timeoflifeapp` in the `local-first-store` baseline (via delta spec, folded at archive), `openspec/config.yaml` inline context, `AGENTS.md` non-negotiables, and `Requirements/FURPS/Timetracking.md` (F1 row + D1 bullet).
- No code, entitlement, identifier, or behavior change of any kind.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `local-first-store`: the "App Group shared container" requirement's container string changes from `group.com.antonkosenko.timeoflife` to `group.com.antonkosenko.timeoflifeapp` (text correction to match shipped code; behavior unchanged).

## Impact

- **Specs**: one delta file `specs/local-first-store/spec.md`; archive folds it into the baseline.
- **Docs**: `openspec/config.yaml` (1 line), `AGENTS.md` (1 line), `Requirements/FURPS/Timetracking.md` (2 spots).
- **Non-goals (explicitly unchanged)**: entitlements, `LocalStore.appGroupID`, bundle ID, and every other identifier; `openspec/changes/archive/**` stays immutable history; the active `rename-app-to-lifio` change is untouched.
