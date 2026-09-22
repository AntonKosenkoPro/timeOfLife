## MODIFIED Requirements

### Requirement: Profile owns secondary destinations
The app SHALL expose account, sync, category management, integrations, export, appearance, and destructive data controls from a profile destination rather than as a primary tab. Activity management SHALL NOT appear in Profile (no activity catalog exists). The Profile "Enable Sync" action SHALL first attempt a silent session restore; when the session is still signed out afterward, it SHALL present the auth flow (`AuthFlowView`) as a sheet framed as optional cross-device sync. The sheet SHALL dismiss on successful sign-in and offer an explicit Cancel close path; dismissing unsigned SHALL return to Profile with local data untouched.

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

### Requirement: Running timer remains globally accessible
The app SHALL keep an active timer visible and directly stoppable while History or Insights is selected. The compact timer SHALL float above the tab bar with a visible gap — never overlapping or touching it.

#### Scenario: Browse while timing
- **WHEN** a timer is running and the user switches from Track to History or Insights
- **THEN** a compact timer displays the entry text and live elapsed duration without obscuring primary navigation

#### Scenario: Stop outside Track
- **WHEN** the user activates Stop on the compact timer
- **THEN** the app saves the entry with the draft's final categories, removes the compact timer, and keeps the current destination selected

#### Scenario: Return to full timer
- **WHEN** the user activates the non-destructive area of the compact timer
- **THEN** the app selects Track and presents the running numeric timer

#### Scenario: Compact timer clears the tab bar
- **WHEN** a timer is running and the user views History or Insights
- **THEN** the compact timer renders fully above the tab bar with daylight between them on every supported screen size

#### Scenario: Track settles after an external stop
- **WHEN** the user returns to Track after stopping the timer from the compact timer
- **THEN** Track shows the settled post-stop state for the same text — never a running timer counting from the stopped start time
