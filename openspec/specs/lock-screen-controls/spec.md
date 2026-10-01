# lock-screen-controls Specification

## Purpose

iOS 18+ Controls (WidgetKit `ControlWidget`) that let the user start and stop the timer from the lock screen, Control Center, or Action button without opening the app or requiring Face ID, via an `alwaysAllowed` background App Intent that writes to the App Group shared container.

## Requirements


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
The Control's App Intent SHALL use `IntentAuthenticationPolicy.alwaysAllowed`, so the intent executes when the device is locked without prompting for Face ID, Touch ID, or passcode. The intent SHALL perform no account authentication of its own: device unlock is the authorization for operating on the active account's file. The intent operates only when an account file is active (the device has been unlocked at least once since boot and a signed-in account is bound); with no active account file the intent SHALL fail gracefully without prompting, writing nothing.

#### Scenario: Tapped while device is locked
- **WHEN** the device is locked (but has been unlocked at least once since boot) and the user taps the Control
- **THEN** the intent executes, writes to the active account's file in the shared container, and returns; no authentication prompt is shown

#### Scenario: No auth prompt for account state
- **WHEN** the user taps the Control regardless of the signed-in account's identity
- **THEN** the intent never prompts for, verifies, or refreshes the user's account session; it acts only on whichever account file is active

#### Scenario: No active account file fails gracefully
- **WHEN** the user taps the Control with no active account file (signed out / never unlocked since boot)
- **THEN** the intent performs no write, shows no auth prompt, and returns the existing graceful-failure result

### Requirement: Graceful failure when database inaccessible
When the active account's file in the shared container is inaccessible — because the device was just rebooted and has never been unlocked since boot (`.completeUntilFirstUserAuthentication` keys evicted), or no active account file exists — the intent SHALL catch the error or absence and return a "please unlock" or locked state to the Control, rather than crashing, creating a new anonymous file, or leaving data inconsistent.

#### Scenario: Cold-boot, never unlocked, Control tapped
- **WHEN** the device was rebooted and has never been unlocked, and the user taps the Control
- **THEN** the Control displays a "please unlock" state; no timer is started; no partial write is committed

#### Scenario: No active account file, Control tapped
- **WHEN** no active account file exists in the shared container and the user taps the Control
- **THEN** the Control displays a locked/empty state; no timer is started, no database file is created, and no anonymous data is read or written

### Requirement: Control reads running state from shared container
The Control SHALL display its toggle state (running vs idle) and, when running, the elapsed time, by reading the running-timer draft from the App Group shared container database (per the local-first-store running-timer-draft requirement).

#### Scenario: Control reflects running timer
- **WHEN** a timer is running (started from the app, a widget, Siri, or another Control instance) and the Control renders
- **THEN** it reads the draft from the shared container and displays the running state with elapsed time

#### Scenario: Control reflects idle state
- **WHEN** no timer is running and the Control renders
- **THEN** it displays the start state, referencing the most-recently-used exact text by name
### Requirement: Availability guard for iOS 18+
The app's deployment target SHALL be iOS 18. No `if #available(iOS 18, *)` guards SHALL exist around Control code. The Control target itself remains deferred (no widget target in `project.yml`); the start/stop, authentication, failure, state-reading, and outbox requirements stay in force as the contract for its future implementation.

#### Scenario: iOS 18+ device
- **WHEN** the user runs the app on iOS 18 or later
- **THEN** the app runs natively with no availability-guard branching; the lock-screen Control is not yet offered (deferred)

#### Scenario: iOS 15–17 device
- **WHEN** a device runs iOS 15, 16, or 17
- **THEN** the app cannot be installed (deployment floor is iOS 18); no Control-absent runtime branch exists

### Requirement: Outbox integration
The Control's App Intent SHALL write the started/stopped entry to the local database and enqueue the corresponding outbox row in the same transaction (per the local-first-store transactional outbox requirement). The sync client drains the outbox on the next foreground; the intent does NOT attempt to sync directly.

#### Scenario: Control-started entry syncs later
- **WHEN** the user starts a timer from the lock-screen Control while offline
- **THEN** the entry and outbox row are written locally; the entry is preserved; on the next foreground with connectivity, the sync client drains the outbox and propagates the entry to the relay
