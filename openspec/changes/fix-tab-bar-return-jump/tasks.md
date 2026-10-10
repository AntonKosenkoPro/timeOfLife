## 1. Grounding & repro

- [x] 1.1 Re-fetch ctx7 SwiftUI docs (`library "SwiftUI"`, `docs "toolbar visibility tab bar hidden"`, library ID `/websites/developer_apple_swiftui`) and confirm `toolbarVisibility(_:for:)` semantics + version pin (iOS 18+) before coding; record library ID + query in the apply log
- [x] 1.2 Record the bug repro on the current tree in the worktree: screen-record Profile→Back on Track, History (with running timer), and Insights, plus one interactive swipe-back commit, one swipe-cancel, and NotesEditor→Back as the no-jump control; save recordings + step list as the before-evidence (bugfix repro rule)

## 2. Stack-owned visibility

- [x] 2.1 Move tab-bar visibility ownership to the three `NavigationStack` roots in `AppShellView.swift` (shown iff own path empty, `.automatic` at root so no conflict), remove the per-destination `.toolbar(.hidden, for: .tabBar)` from Profile and the pushed entry form, keep agreeing backstops on Manage Categories and NamePicker, and convert the Track name row's caller-local `NavigationLink` into the `ShellRoute.namePicker` path value (device spike: stack-level wins unconditionally, so every root push must be path-observed); keep per-tab path independence and all accessibility ids
- [x] 2.2 Join the root height change to the same transaction (Track `AdaptiveVerticalLayout` spacing + History/Insights `safeAreaInset` compact-timer slot animate with the bar; no measurement-feedback loop, Theme-only, no new strings)
- [x] 2.3 Add/extend `AppShellViewModel` path-visibility unit tests (empty vs non-empty per tab, independence across tabs) and keep existing shell tests green

## 3. Gesture hardening & spike verdict

- [x] 3.1 Verify swipe-back commit, swipe-cancel (bar stays hidden, destination unchanged), and tab-switch flows against the new spec scenarios; record which gestures still lag after 2.1–2.2
- [x] 3.2 If and only if swipe-commit still lags, add the minimal guarded supplement (tab-identity-aware, no bare `onDisappear` leak) and re-verify 3.1; otherwise leave lifecycle hacks out and note the verdict in the change log

## 4. Verify & close out

- [x] 4.1 Run `swiftlint lint --strict` (fix all findings), warning-as-errors `xcodebuild build`, and the iOS test suite green per `docs/ios-test-loop.md` (one `xcodebuild` at a time); confirm `go test ./...` unaffected (no backend touch)
- [x] 4.2 Re-run the identical 1.2 repro on the fixed tree and attach the after-evidence (same steps, same tabs/gestures); reopen on any surviving jump instead of guessing
- [x] 4.3 Re-check `Requirements/FURPS/*.md` rows for app-shell/nav behavior, run `openspec validate --all --strict`, and update `docs/project-context.md` only if architecture/contract/run steps changed (keep `AGENTS.md` short per repo rule)
