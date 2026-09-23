## MODIFIED Requirements

### Requirement: Sync triggers
The sync client SHALL run on: (1) app enters foreground, (2) connectivity restores (NWPathMonitor `.satisfied`), (3) manual "Sync now" action, (4) History pull-to-refresh. A trigger arriving while a cycle is already in flight SHALL join it (await the in-flight cycle's result) instead of starting a second concurrent cycle. On macOS, a timer-based background sync (every N minutes while running) SHALL be added; on iOS, background task scheduling SHALL NOT be used (unreliable).

#### Scenario: Foreground trigger
- **WHEN** the app enters the foreground
- **THEN** the sync client runs a drain-outbox + delta-pull cycle (if signed in)

#### Scenario: Connectivity restored
- **WHEN** connectivity transitions to `.satisfied` while signed in
- **THEN** the sync client runs a cycle

#### Scenario: Manual sync
- **WHEN** the user taps "Sync now" in Profile
- **THEN** the sync client runs a cycle and updates the displayed "Last synced" timestamp on completion

#### Scenario: History pull trigger
- **WHEN** the user pulls to refresh on the populated History list while signed in and online
- **THEN** the sync client runs a cycle (or joins the in-flight one) and the pull awaits its result

#### Scenario: Join instead of fork
- **WHEN** any trigger (pull, Profile "Sync now", foreground, connectivity) arrives while a cycle is in flight
- **THEN** no second cycle starts; the arriving caller awaits the in-flight cycle's outcome
