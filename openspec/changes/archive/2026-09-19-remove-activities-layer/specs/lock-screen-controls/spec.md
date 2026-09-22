## MODIFIED Requirements

### Requirement: Lock-screen start/stop Control
The system SHALL provide an iOS 18+ `ControlWidget` (a toggle Control) that the user can place on the lock screen, Control Center, or Action button. Tapping the Control when no timer is running SHALL start a timer against the most-recently-used exact entry text with that entry's full ordered categories (or prompt on first use if no history). Tapping when a timer is running SHALL stop and save the entry with the draft's final categories. The Control SHALL NOT open the app in the foreground.

#### Scenario: Start from lock screen
- **WHEN** no timer is running and the user taps the Control on the lock screen
- **THEN** a timer starts against the most-recently-used exact text with its inherited categories; the Control display updates to show "Stop (running)" and the elapsed time; the app is not brought to the foreground

#### Scenario: Stop from lock screen
- **WHEN** a timer is running and the user taps the Control on the lock screen
- **THEN** the timer stops, the entry is saved to the local database with `source='control'`, and the Control display reverts to the start state

#### Scenario: First use with no history
- **WHEN** the user taps the Control for the first time and the local database has no committed entries
- **THEN** the Control displays a state indicating the user must open the app to enter at least one name; no timer is started

### Requirement: Control reads running state from shared container
The Control SHALL display its toggle state (running vs idle) and, when running, the elapsed time, by reading the running-timer draft from the App Group shared container database (per the local-first-store running-timer-draft requirement).

#### Scenario: Control reflects running timer
- **WHEN** a timer is running (started from the app, a widget, Siri, or another Control instance) and the Control renders
- **THEN** it reads the draft from the shared container and displays the running state with elapsed time

#### Scenario: Control reflects idle state
- **WHEN** no timer is running and the Control renders
- **THEN** it displays the start state, referencing the most-recently-used exact text by name
