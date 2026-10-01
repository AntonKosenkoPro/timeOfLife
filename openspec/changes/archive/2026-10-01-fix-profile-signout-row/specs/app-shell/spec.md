## MODIFIED Requirements

### Requirement: Profile owns secondary destinations
The app SHALL expose account, sync, category management, and destructive data controls from a profile destination rather than as a primary tab. The profile destination SHALL be signed-in-only: it SHALL NOT present an Enable Sync row or auth-flow sheet, and the auth flow SHALL NOT be presented from Profile as a sheet. Because the launch auth gate guarantees a signed-in user, the account and sync state shown in Profile SHALL reflect the active signed-in account at all times. The profile destination SHALL NOT expose integrations, export, appearance, or data-and-privacy placeholder rows, and activity management SHALL NOT appear in Profile (no activity catalog exists). Destructive rows in Profile (Sign Out, Erase local data) SHALL share one list-row visual contract: the shared list row geometry with a leading icon and the danger tint.

#### Scenario: Open profile while signed out
- **WHEN** a user without an account attempts to reach the profile destination
- **THEN** the auth gate precedes it: the profile destination is unreachable, and the auth flow is the only presented surface until sign-in completes

#### Scenario: Return from profile
- **WHEN** the user dismisses or navigates back from the profile destination
- **THEN** the previously selected primary destination and its state are restored

#### Scenario: Enable Sync with a restorable session
- **WHEN** the launch gate runs with a valid restorable session
- **THEN** the silent restore signs the user in with no auth flow shown and the shell is presented directly

#### Scenario: Enable Sync without a restorable session
- **WHEN** the launch gate runs with no restorable session
- **THEN** the required-voice auth flow is presented full-screen (never a silent no-op into the shell)

#### Scenario: Sign in from the sheet
- **WHEN** the user completes sign-in in the launch-gate auth flow
- **THEN** the shell replaces the auth flow with Track selected and Profile shows the signed-in account and sync state

#### Scenario: Dismiss the sheet unsigned
- **WHEN** the user attempts to leave the launch-gate auth flow without signing in
- **THEN** no dismiss or cancel path is offered: the gate remains full-screen and local data stays untouched

#### Scenario: No placeholder rows
- **WHEN** the user opens Profile
- **THEN** no Integrations, Export, Appearance, or Data & Privacy rows are shown, and every visible row is tappable or a live status

#### Scenario: Sign out row parity
- **WHEN** the user opens Profile
- **THEN** Sign Out renders with the same list-row geometry, leading icon, and danger tint as Erase local data, keeps the `ProfileSignOutButton` accessibility identifier, and tapping it signs the user out with no confirmation
