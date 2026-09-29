# lock-screen-controls delta spec

## MODIFIED Requirements

### Requirement: Lock-screen start/stop Control
The system SHALL provide an iOS 18+ `ControlWidget` (a toggle Control) that the user can place on the lock screen, Control Center, or Action button. The Control SHALL operate on the active account's local database file without performing any authentication of its own — device unlock is the authorization, per the local-first-store active-account-file requirement. Tapping the Control when no timer is running SHALL start a timer against the most-recently-used exact entry text with that entry's full ordered categories (or prompt on first use if no history). Tapping when a timer is running SHALL stop and save the entry with the draft's final categories. The Control SHALL NOT open the app in the foreground.

#### Scenario: Start from lock screen
- **WHEN** no timer is running, the device is unlocked, and the user taps the Control on the lock screen
- **THEN** a timer starts against the active account file's most-recently-used exact text with its inherited categories; the Control display updates to show "Stop (running)" and the elapsed time; the app is not brought to the foreground

#### Scenario: Stop from lock screen
- **WHEN** a timer is running and the user taps the Control on the lock screen
- **THEN** the timer stops, the entry is saved to the active account's local database file with `source='control'`, and the Control display reverts to the start state

#### Scenario: First use with no history
- **WHEN** the user taps the Control for the first time and the active account's local database has no committed entries
- **THEN** the Control displays a state indicating the user must open the app to enter at least one name; no timer is started

#### Scenario: Signed out with no active account file
- **WHEN** no active account file exists (the user is signed out at the auth gate) and the user taps the Control
- **THEN** the Control displays a locked/empty state; no timer is started, no entry is written, and no anonymous data is ever read or shown

#### Scenario: Control never exposes another account's data
- **WHEN** an account file is dormant and a different account's file is active, and the Control renders or is tapped
- **THEN** the Control reads and writes only the active account's file and never surfaces data from the dormant account's file

### Requirement: No authentication required
The Control's App Intent SHALL use `IntentAuthenticationPolicy.alwaysAllowed`, so the intent executes when the device is locked without prompting for Face ID, Touch ID, or passcode. The intent SHALL perform no account authentication of its own: device unlock is the authorization for operating on the active account's file.

#### Scenario: Tapped while device is locked
- **WHEN** the device is locked (but has been unlocked at least once since boot) and the user taps the Control
- **THEN** the intent executes, writes to the active account's file in the shared container, and returns; no authentication prompt is shown

#### Scenario: No auth prompt for account state
- **WHEN** the user taps the Control regardless of the signed-in account's identity
- **THEN** the intent never prompts for, verifies, or refreshes the user's account session; it acts only on whichever account file is active

### Requirement: Graceful failure when database inaccessible
When the active account's file in the shared container is inaccessible — because the device was just rebooted and has never been unlocked since boot (`.completeUntilFirstUserAuthentication` keys evicted), or no active account file exists — the intent SHALL catch the error or absence and return a "please unlock" or locked state to the Control, rather than crashing, creating a new anonymous file, or leaving data inconsistent.

#### Scenario: Cold-boot, never unlocked, Control tapped
- **WHEN** the device was rebooted and has never been unlocked, and the user taps the Control
- **THEN** the Control displays a "please unlock" state; no timer is started; no partial write is committed

#### Scenario: No active account file, Control tapped
- **WHEN** no active account file exists in the shared container and the user taps the Control
- **THEN** the Control displays a locked/empty state; no timer is started, no database file is created, and no anonymous data is read or written