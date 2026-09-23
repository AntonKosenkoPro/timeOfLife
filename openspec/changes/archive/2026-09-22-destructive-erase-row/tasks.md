## 1. Destructive row styling

- [x] 1.1 Move danger styling inside the erase row label in `ProfileView.onDeviceSection` so the trash icon and title both render in `Theme.danger` (remove reliance on the swallowed outer modifier); give the control `Button(role: .destructive)`; keep section, order, footer, title copy, and alert behavior unchanged.
- [x] 1.2 Verify no other `ListRow` caller changes rendering (regular rows keep `Theme.accentPrimary` icon / `Theme.textPrimary` title); only add a reusable `ListRow` tint/destructive path if review prefers it over the local override.

## 2. Verification

- [x] 2.1 Visual check: Profile "On This Device" shows a red trash icon + red "Erase local data" title, distinct from the regular Categories row, in light and dark appearances and EN + RU locales; confirmation alert still shows destructive Erase + Cancel with the permanence message.
- [x] 2.2 Run iOS checks green: `swiftlint lint --strict`, `xcodebuild -scheme TimeOfLife -destination 'generic/platform=iOS Simulator' build`, and the relevant test suite (`xcodebuild test -scheme TimeOfLife`); `gofmt`-style scope N/A (no backend change).
- [x] 2.3 Re-check `Requirements/FURPS/Timetracking.md` F5 (sign-out preserves data; explicit erase wipes) and `Design/INTERACTIONS.md` Profile destination ("Erase local data" destructive, confirmed) for alignment; confirm no doc/spec drift beyond this change's delta.
