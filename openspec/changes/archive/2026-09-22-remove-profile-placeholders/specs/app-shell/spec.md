## MODIFIED Requirements

### Requirement: Profile owns secondary destinations
The app SHALL expose account, sync, category management, and destructive data controls from a profile destination rather than as a primary tab. The profile destination SHALL NOT expose integrations, export, appearance, or data-and-privacy placeholder rows. Activity management SHALL NOT appear in Profile (no activity catalog exists). The Profile "Enable Sync" action SHALL first attempt a silent session restore; when the session is still signed out afterward, it SHALL present the auth flow (`AuthFlowView`) as a sheet framed as optional cross-device sync. The sheet SHALL dismiss on successful sign-in and offer an explicit Cancel close path; dismissing unsigned SHALL return to Profile with local data untouched.

#### Scenario: Open profile while signed out
- **WHEN** a user without an account opens the profile destination
- **THEN** local configuration remains available and account sync is presented as an optional action

#### Scenario: Return from profile
- **WHEN** the user dismisses or navigates back from the profile destination
- **THEN** the previously selected primary destination and its state are restored

#### Scenario: Enable Sync with a restorable session
- **WHEN** a signed-out user with a valid Keychain session taps "Enable Sync"
- **THEN** the silent restore signs them in with no sheet shown

#### Scenario: Enable Sync without a restorable session
- **WHEN** a signed-out user with no restorable session taps "Enable Sync"
- **THEN** the auth flow sheet opens (never a silent no-op), voiced as optional cross-device sync

#### Scenario: Sign in from the sheet
- **WHEN** the user completes sign-in inside the sheet
- **THEN** the sheet dismisses and Profile shows the signed-in sync state

#### Scenario: Dismiss the sheet unsigned
- **WHEN** the user cancels the sheet without signing in
- **THEN** Profile returns unsigned with local data and the outbox untouched

#### Scenario: No placeholder rows
- **WHEN** the user opens Profile in any auth state
- **THEN** no Integrations, Export, Appearance, or Data & Privacy rows are shown, and every visible row is tappable or a live status
