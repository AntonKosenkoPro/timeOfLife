# App Shell Specification — MODIFIED (account-bound-local-data)

## MODIFIED Requirements

### Requirement: Three primary destinations
The app SHALL provide Track, History, and Insights as its primary destinations, and SHALL identify Track as the destination for starting and controlling a timer. The History destination SHALL present committed time entries as a day-grouped, read-only list (see `history-entry-list` capability). The Insights destination SHALL present a period-scoped breakdown of committed tracked time with a hero total (see `insights-breakdown` capability), replacing the empty-state placeholder whenever committed entries exist. The History destination SHALL show the navigation bar (inline title and Profile button) at rest and collapse it on scroll; the Profile button remains present on Track and Insights. The app SHALL require authentication before presenting any primary destination: when the user is signed out, the app SHALL render the auth flow full-screen in place of the shell and MUST NOT render Track, History, Insights, or the tab bar; primary destinations become reachable only after sign-in.

#### Scenario: Local launch
- **WHEN** the user launches the app signed out, with no account or active timer
- **THEN** the auth flow is presented full-screen instead of Track and the primary destinations are not reachable until sign-in succeeds

#### Scenario: Switching destinations
- **WHEN** the user selects History or Insights
- **THEN** the selected destination becomes visible without changing timer state or discarding the state of the previous destination

#### Scenario: Profile access on History
- **WHEN** the user is on History at rest (list at top) and wants to open Profile
- **THEN** the Profile button is visible in the navigation bar and opens Profile

#### Scenario: Insights shows breakdown
- **WHEN** the user selects Insights with committed entries on record
- **THEN** the period breakdown with hero total is shown instead of the empty-state placeholder

#### Scenario: Auth gate is not a sheet
- **WHEN** the user is signed out at launch
- **THEN** the auth flow covers the full screen with no shell visible behind it, and there is no way to dismiss it into the app without signing in

### Requirement: Profile owns secondary destinations
The app SHALL expose account, sync, category management, and destructive data controls from a profile destination rather than as a primary tab. The profile destination SHALL be signed-in-only: it SHALL NOT present an Enable Sync row or auth-flow sheet, and the auth flow SHALL NOT be presented from Profile as a sheet. Because the launch auth gate guarantees a signed-in user, the account and sync state shown in Profile SHALL reflect the active signed-in account at all times. The profile destination SHALL NOT expose integrations, export, appearance, or data-and-privacy placeholder rows, and activity management SHALL NOT appear in Profile (no activity catalog exists).

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

### Requirement: Auth gate copy is required voice
The auth flow presented at launch SHALL use required-voice copy that frames sign-in as the prerequisite for using the tracker (for example, "Log in to start tracking"), and MUST NOT use optional-sync voice framing the account as an optional cross-device feature.

#### Scenario: Welcome copy states the requirement
- **WHEN** the signed-out user sees the auth flow's welcome screen at launch
- **THEN** the copy states that logging in is required to start tracking, with no "Enable Sync" or "optional" framing

#### Scenario: Copy is localized
- **WHEN** the auth gate is rendered in each supported locale
- **THEN** the required-voice copy is provided for that locale alongside the English strings