## MODIFIED Requirements

### Requirement: Timer draft holds text and live categories
The `timer_state` singleton SHALL hold `(activity_text, ordered category_ids, notes, started_at, status)` for the running draft. Toggles SHALL rewrite the snapshot in the same chokepoint transaction. Notes saves SHALL rewrite only the notes field in the same chokepoint transaction. Start-time edits SHALL rewrite only the `started_at` field in the same chokepoint transaction (text, categories, and notes untouched). Stop SHALL create the entry from the draft (text + final categories + final notes + final start) and clear it.

#### Scenario: Crash restores draft tags
- **WHEN** the app restarts with a persisted running draft
- **THEN** the timer resumes with the locked text and the tags as last left

#### Scenario: Crash restores draft notes
- **WHEN** the app restarts with a persisted running draft holding notes
- **THEN** the timer resumes with the draft notes as last left, and Stop saves the entry with those notes unless edited further

#### Scenario: Mid-run notes edit rewrites the snapshot
- **WHEN** the user saves notes while running
- **THEN** only the draft notes field updates in the same chokepoint transaction; text, categories, and `started_at` are untouched

#### Scenario: Mid-run start edit rewrites only the start field
- **WHEN** the user confirms a new start time while running
- **THEN** only the draft `started_at` field updates in the same chokepoint transaction; text, categories, and notes are untouched, and no outbox row is written (the draft is never synced — Stop enqueues the single entry create)
