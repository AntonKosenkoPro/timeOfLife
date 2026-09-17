# Design: Erase Resets Auth Flow

## Context

- `ProfileView.eraseLocalData` (private view function) currently performs exactly two actions: `LocalStore.eraseAll()` (wipes state tables + outbox + undo buffer) and `AuthService.logout()`.
- The auth flow (`AuthFlowView`, presented as a sheet by `present-enable-sync-sheet`) pushes onto the shared `AppNavigationStack.path` (`@Published var path: [AppRoute]`). Completing or abandoning the email step leaves `[.emailEntry, .otpEntry(email)]` on the stack; erase touches none of it.
- Consequence: after erase, "Enable Sync" reopens the sheet onto the stale OTP screen pre-filled with the previous email — inconsistent with the fresh-install-like state the erase promises (empty DB, signed out).

## Goals / Non-Goals

Goals: after erase, "Enable Sync" opens `AuthFlowView` at the flow's start with an empty email field (fresh `EmailEntryViewModel`).

Non-goals: no change to plain sign-out behavior; no change to `EnableSyncPresenter` / mid-flow abandon-resume; no auth-flow screen changes; no store or backend changes.

## Decisions

### D1: Reset the path in `ProfileView.eraseLocalData`

The reset (`container.navigation.path = []`, i.e. assigning the empty array) lives in the same erase handler as the wipe and the sign-out. Erase is defined as returning the device to a fresh-install-like state; the auth navigation state is part of that state.

*Alternatives considered*:

- Reset inside `AuthService.logout()` — wrong layer: `logout` also fires on background 401/refresh-rejection paths, and a plain sign-out (Profile → sign out, keeping data) legitimately leaves the flow state the user walked; resetting there would change behavior outside this change's scope.
- Reset in `EnableSyncPresenter` on tap — would also erase progress when the user abandons a legitimate mid-flow attempt (entering OTP, reopening later); changing that resume behavior is out of scope.

## Risks / Trade-offs

- [Risk] Resetting while the auth sheet is somehow open mid-erase → Mitigation: erase is confirmed from Profile with the sheet closed; the sheet is not presented during erase.
- [Risk] Other `AppRoute` entries on the shared stack → Mitigation: assigning `[]` clears whatever routes remain; after erase the only consumer is the auth flow opening fresh.

## Migration Plan

None. One-line view-level reset; no persisted formats, no contract, no flags. Rollback = remove the line.

## Open Questions

None.