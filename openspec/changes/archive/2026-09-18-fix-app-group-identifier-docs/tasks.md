## 1. Doc correction

- [x] 1.1 Update `openspec/config.yaml` non-negotiables App Group to `group.com.antonkosenko.timeoflifeapp` (structure untouched)
- [x] 1.2 Update `AGENTS.md` chokepoint bullet App Group to `group.com.antonkosenko.timeoflifeapp`
- [x] 1.3 Update `Requirements/FURPS/Timetracking.md` App Group in the F1 row and the D1 bullet to `group.com.antonkosenko.timeoflifeapp`

## 2. Verification

- [x] 2.1 Run `rg "group.com.antonkosenko.timeoflife"` repo-wide and confirm the only remaining hits are `openspec/changes/archive/**` history; run `rg "group.com.antonkosenko.timeoflifeapp"` and confirm code (entitlements, `LocalStore`), README, project-context, config, AGENTS, FURPS, and this change's delta all agree
- [x] 2.2 Confirm `git diff` touches prose only (no `.swift`, `.entitlements`, `project.yml`, or baseline-spec files); `openspec validate fix-app-group-identifier-docs --type change` valid
