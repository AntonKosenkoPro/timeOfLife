## MODIFIED Requirements

### Requirement: Profile owns secondary destinations
The app SHALL expose account, sync, category management, and destructive data controls from a profile destination rather than as a primary tab. The profile destination SHALL NOT expose integrations, export, appearance, or data-and-privacy placeholder rows. Activity management SHALL NOT appear in Profile (no activity catalog exists). The Profile "Enable Sync" action SHALL first attempt a silent session restore; when the session is still signed out afterward, it SHALL present the auth flow (`AuthFlowView`) as a sheet framed as optional cross-device sync. The sheet SHALL dismiss on successful sign-in and offer an explicit Cancel close path; dismissing unsigned SHALL return to Profile with local data untouched. The profile destination SHALL display the running app version as footer text at the bottom of Profile: the marketing version and build number as `v1.0.0 (1)` on Release builds and `v1.0.0 (1) • Debug` on Debug builds, right-aligned caption styling, non-tappable diagnostic metadata with no row or card background.

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

#### Scenario: Version label on Release build
- **WHEN** the user opens Profile in a Release build (including TestFlight)
- **THEN** the bottom of Profile shows the marketing version and build number as footer text `v1.0.0 (1)`, right-aligned, caption-styled, with no row or card background, and non-tappable

#### Scenario: Version label on Debug build
- **WHEN** the user opens Profile in a Debug build
- **THEN** the footer version text appends the build-configuration suffix as `v1.0.0 (1) • Debug`

#### Scenario: Version label is stable metadata
- **WHEN** the user opens Profile in any auth state, with any Dynamic Type size or VoiceOver enabled
- **THEN** the version label remains readable, is exposed to accessibility as a static label, and never triggers navigation or an action
