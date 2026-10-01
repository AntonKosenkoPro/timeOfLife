## Context

See proposal.md Why. Current state (`ProfileView.accountSection`): Sync status + Sync now render through shared `ListRow` (icon column 28pt, `minHeight` 44pt, `spacingSmall` vertical padding); Sign Out is a bare `Button(L10n.timerSignOut.text, role: .destructive)` — plain text, no icon column, different height/inset, system red instead of `Theme.danger`, and the `timer.*` key is mis-scoped for a Profile row. Reference shape is the Erase local data row: `Button(role: .destructive) { ... } label: { ListRow(title:icon:tint: Theme.danger) }`. Constraints: Theme-only colors; L10n for strings (U4: both lproj + enum); `ProfileSignOutButton` id stable (automation); iOS 18+ floor so the chosen SF Symbol is always available; `RootView.GateSignOutButton` shares the sign-out string but is a centered `VStack` placeholder, not a List — key rename only, no restyle.

## Goals / Non-Goals

**Goals:**
- Sign Out visually matches Erase local data (icon column, row height, danger tint) with zero behavior change.
- Contract locked by a lightweight SwiftTesting test following repo patterns (no new test infra).

**Non-Goals:**
- No sign-out copy change (en "Sign Out" / ru "Выйти" verbatim), no COMPONENTS.md redesign beyond the already-drifted `tint` note.
- No gate placeholder restyle, no auth/sync/data changes, no new reusable component.

## Decisions

- **Reuse `ListRow(title:icon:tint: Theme.danger)` inside `Button(role: .destructive)`, keep `ProfileSignOutButton` id.** Rationale: one-line parity with Erase; `tint` is required because `ListRow`'s explicit inner styles beat any inherited `foregroundStyle` (documented in `ListRow.swift`); stable id avoids automation breakage. Alternative (custom HStack) rejected — duplicates geometry.
- **Icon `rectangle.portrait.and.arrow.right`.** Rationale: iOS-native sign-out metaphor, light glyph that holds at `.body` in the 28pt column. Alternatives considered: `door.left.hand.open` / `door.right.hand.open` (literal but heavier, RTL direction question), `power` (wrong metaphor), `person.crop.circle.badge.xmark` (reads as delete-account, confusable with Erase). Decision per user pick (explore: lean).
- **Rename `timer.signOut` → `profile.signOut` (same copy).** Rationale: the key is mis-scoped — a Profile row under `timer.*`; the rename puts it with the other `profile.*` keys. Single key moves (not add): `ProfileView` + `RootView` gate both adopt `L10n.profileSignOut`, `timer.signOut` rows are removed from en/ru, `LocalizationTests` count stays 146. Alternative (keep `timer.signOut`) rejected per user call — cleanliness wins, pre-release so no on-disk compat concern. Alternative (two keys, one per call site) rejected — identical copy duplicated for no benefit.
- **Tests: logic-level contract, no ViewInspector.** Rationale: repo tests assert view-model/accessibility strings, not view hierarchies, and add no snapshot/ViewInspector deps. Test pins the row contract (icon name resolves via `UIImage(systemName:)`, tint is `Theme.danger`, id literal unchanged) so a future plain-text regression fails. Alternative (full UI/snapshot test) rejected as disproportionate for a 5-line visual fix.

## Risks / Trade-offs

- [Risk] Chosen symbol renders heavy/light vs `trash`/`tag` at 28pt → Mitigation: manual smoke in light/dark + Dynamic Type large; swap symbol only (spec scenario unchanged).
- [Risk] `Theme.danger` vs system destructive red contrast in dark mode → Mitigation: smoke both appearances; Erase already ships this tint so parity is the safer side.
- [Risk] View-level regression not caught by logic test (icon typo still compiles) → Mitigation: test asserts `UIImage(systemName:)` non-nil; manual Profile screenshot in PR.
- [Risk] Key rename misses a call site (`timer.signOut` lingers) → Mitigation: grep for `timer.signOut`/`timerSignOut` must be zero hits after; `LocalizationTests` (allCases + per-locale resolve) green.
- [Risk] `Design/COMPONENTS.md` `ListRow` block lacks `tint` (pre-existing drift) → Mitigation: update the signature/visual note in the same change, no behavior claim change.
