## 1. Profile sign-out row

- [x] 1.1 Wrap Sign Out in `ListRow(title: L10n.profileSignOut.text, icon: "rectangle.portrait.and.arrow.right", tint: Theme.danger)` inside `Button(role: .destructive)` in `ProfileView.accountSection`, keeping `ProfileSignOutButton` id and `logout()` action
- [x] 1.2 Rename L10n key `timer.signOut` → `profile.signOut` (same en "Sign Out" / ru "Выйти" copy): replace `timerSignOut` case with `profileSignOut` in `String+Localized.swift`, move the rows in `en`/`ru` `Localizable.strings`, update `ProfileView` + `RootView` gate call sites, grep proves zero `timer.signOut`/`timerSignOut` hits
- [x] 1.3 Add SwiftTesting contract coverage for the sign-out row (icon resolves via `UIImage(systemName:)`, danger tint, stable id) following existing `*AccessibilityTests` patterns
- [x] 1.4 Update `Design/COMPONENTS.md` `ListRow` signature/visual note to include the existing `tint` parameter

## 2. Verify

- [x] 2.1 Run `swiftlint lint --strict`, `xcodebuild -scheme TimeOfLife -destination '<available simulator>' build` and `test` green (one xcodebuild at a time per `docs/ios-test-loop.md`; `LocalizationTests` allCases stays 146)
- [ ] 2.2 Manual smoke: Profile light/dark, Dynamic Type large, en + ru — Sign Out matches Erase local data row geometry/icon/tint with unchanged copy; tap signs out; gate placeholder visually unchanged
- [x] 2.3 Run `openspec validate --all --strict` green
