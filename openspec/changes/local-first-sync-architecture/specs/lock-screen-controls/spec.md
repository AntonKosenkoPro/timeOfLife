## Purpose

iOS 18+ Controls (WidgetKit `ControlWidget`) that let the user start and stop the timer from the lock screen, Control Center, or Action button without opening the app or requiring Face ID, via an `alwaysAllowed` background App Intent that writes to the App Group shared container.

## ADDED Requirements

### Requirement: Lock-screen start/stop Control
The system SHALL provide an iOS 18+ `ControlWidget` (a toggle Control) that the user can place on the lock screen, Control Center, or Action button. Tapping the Control when no timer is running SHALL start a timer against the most-recently-used activity (or prompt on first use if no history). Tapping when a timer is running SHALL stop and save the entry. The Control SHALL NOT open the app in the foreground.

#### Scenario: Start from lock screen
- **WHEN** no timer is running and the user taps the Control on the lock screen
- **THEN** a timer starts against the most-recently-used activity; the Control display updates to show "Stop (running)" and the elapsed time; the app is not brought to the foreground

#### Scenario: Stop from lock screen
- **WHEN** a timer is running and the user taps the Control on the lock screen
- **THEN** the timer stops, the entry is saved to the local database with `source='control'`, and the Control display reverts to the start state

#### Scenario: First use with no history
- **WHEN** the user taps the Control for the first time and the local database has no activities
- **THEN** the Control displays a state indicating the user must open the app to set up at least one activity; no timer is started

### Requirement: No authentication required
The Control's App Intent SHALL use `IntentAuthenticationPolicy.alwaysAllowed`, so the intent executes when the device is locked without prompting for Face ID, Touch ID, or passcode.

#### Scenario: Tapped while device is locked
- **WHEN** the device is locked (but has been unlocked at least once since boot) and the user taps the Control
- **THEN** the intent executes, writes to the shared container database, and returns; no authentication prompt is shown

### Requirement: Graceful failure when database inaccessible
When the shared container database is inaccessible because the device was just rebooted and has never been unlocked since boot (`.completeUntilFirstUserAuthentication` keys evicted), the intent SHALL catch the database-open error and return a "please unlock" state to the Control, rather than crashing or leaving data inconsistent.

#### Scenario: Cold-boot, never unlocked, Control tapped
- **WHEN** the device was rebooted and has never been unlocked, and the user taps the Control
- **THEN** the Control displays a "please unlock" state; no timer is started; no partial write is committed

### Requirement: Control reads running state from shared container
The Control SHALL display its toggle state (running vs idle) and, when running, the elapsed time, by reading the running-timer state from the App Group shared container database (per the local-first-store running-timer-state requirement).

#### Scenario: Control reflects running timer
- **WHEN** a timer is running (started from the app, a widget, Siri, or another Control instance) and the Control renders
- **THEN** it reads the timer state from the shared container and displays the running state with elapsed time

#### Scenario: Control reflects idle state
- **WHEN** no timer is running and the Control renders
- **THEN** it displays the start state, referencing the most-recently-used activity by name

### Requirement: Availability guard for iOS 18+
The Control SHALL be available only on iOS 18+ and SHALL be absent (no Control offered) on iOS 15–17. The app's deployment target SHALL remain iOS 15. The Control code SHALL be wrapped in `if #available(iOS 18, *)` guards so the app builds and runs on iOS 15+.

#### Scenario: iOS 18+ device
- **WHEN** the user runs the app on iOS 18 or later
- **THEN** the Time of Life Control is available to add to the lock screen / Control Center

#### Scenario: iOS 15–17 device
- **WHEN** the user runs the app on iOS 15, 16, or 17
- **THEN** no Control is offered; the app's other features work normally

### Requirement: Outbox integration
The Control's App Intent SHALL write the started/stopped entry to the local database and enqueue the corresponding outbox row in the same transaction (per the local-first-store transactional outbox requirement). The sync client drains the outbox on the next foreground; the intent does NOT attempt to sync directly.

#### Scenario: Control-started entry syncs later
- **WHEN** the user starts a timer from the lock-screen Control while offline
- **THEN** the entry and outbox row are written locally; the entry is preserved; on the next foreground with connectivity, the sync client drains the outbox and propagates the entry to the relay