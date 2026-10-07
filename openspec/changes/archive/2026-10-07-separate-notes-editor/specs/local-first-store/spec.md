## MODIFIED Requirements

### Requirement: Running timer state persistence
The system SHALL persist the running timer's draft state (entry text, ordered category ids, notes, started_at, status) in the local database, not solely in app memory, so that the timer survives app crashes and is readable by widgets and lock-screen Controls. Widgets and Controls SHALL continue to read only text/status/elapsed and SHALL ignore the notes column.

#### Scenario: Timer survives app crash
- **WHEN** a timer is running and the app crashes or is killed by the OS
- **THEN** on next launch the app reads the draft from the database and resumes the running-timer UI (shows the elapsed time, the locked text, the tags as left, and the draft notes as left)

#### Scenario: Control displays running timer
- **WHEN** a lock-screen Control or widget renders while a timer is running
- **THEN** it reads the draft from the shared container database and displays the running status and elapsed time

### Requirement: Timer draft holds text and live categories
The `timer_state` singleton SHALL hold `(activity_text, ordered category_ids, notes, started_at, status)` for the running draft. Toggles SHALL rewrite the snapshot in the same chokepoint transaction. Notes saves SHALL rewrite only the notes field in the same chokepoint transaction. Stop SHALL create the entry from the draft (text + final categories + final notes) and clear it.

#### Scenario: Crash restores draft tags
- **WHEN** the app restarts with a persisted running draft
- **THEN** the timer resumes with the locked text and the tags as last left

#### Scenario: Crash restores draft notes
- **WHEN** the app restarts with a persisted running draft holding notes
- **THEN** the timer resumes with the draft notes as last left, and Stop saves the entry with those notes unless edited further

#### Scenario: Mid-run notes edit rewrites the snapshot
- **WHEN** the user saves notes while running
- **THEN** only the draft notes field updates in the same chokepoint transaction; text, categories, and `started_at` are untouched
