## 1. Shell route + per-tab paths

- [x] 1.1 Add `ShellRoute` (profile, history entry-form by id/snapshot, name-picker context) and per-tab paths (`trackPath`, `historyPath`, `insightsPath`) to `AppShellViewModel` alongside `selectedTab`; decide entry-form payload (id vs. snapshot) without changing spec behavior.
- [x] 1.2 Rebuild `AppShellView.navigationRoot` on `NavigationStack(path:)` per tab with `.navigationDestination(for: ShellRoute.self)`; remove shared `isShowingProfile` flag and its global `onChange` reload.
- [x] 1.3 Fold History entry EDIT/LOCKED (`navigationDestination(item: $editingEntry)`) into `historyPath`; keep CREATE Log Time as a sheet with its inner stack.
- [x] 1.4 Fold Track `NamePicker` link and LogTime name `NavigationLink` into the owning tab path; simplify `LogTimeView.embeddedInNavigationStack` split (pushed = chrome-only, sheet = own stack).
- [x] 1.5 Move Profile-exit `trackVM.load()` to the per-tab Profile-route pop transition (once-on-exit; Categories/editor traffic causes no reload).

## 2. Tab-bar visibility + chrome

- [x] 2.1 Hide the tab bar on every pushed destination (Profile, ManageCategories, pushed entry form, NamePicker) via destination-level `.toolbar(.hidden, for: .tabBar)`; verify pop restores the bar with tab state intact.
- [x] 2.2 Verify toolbar scope: shell Profile/[+] items stay on roots only; pushed pages show their own chrome (Back + editor/picker actions), never a second Profile button.
- [x] 2.3 Verify compact-timer inset stays on History/Insights roots, clears the tab bar, and does not float over pushes.

## 3. Verification (S5)

- [x] 3.1 Add/extend UI tests: open Profile per tab (tabs hidden, Back exits), Profile→Categories depth stays hidden, History→entry→NamePicker depth stays hidden, per-tab independence (Profile on Track, History root clean), exit reloads Track data.
- [x] 3.2 Run `swiftlint lint --strict`, warning-as-error `xcodebuild` build, and `xcodebuild test -scheme TimeOfLife` per `docs/ios-test-loop.md` (one xcodebuild at a time); run `go test ./...` (unaffected, sanity).
- [x] 3.3 Re-check `Requirements/FURPS/*.md` rows for shell/nav; confirm no conflicts or fix docs.
- [x] 3.4 Update docs if nav contract changed: `docs/project-context.md` (shell paragraph), `README.md` smoke checklist if the Profile path steps changed; keep `AGENTS.md` short.
- [x] 3.5 Run `openspec validate --all --strict` green.
