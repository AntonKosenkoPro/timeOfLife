## ADDED Requirements

### Requirement: Planner tasks persist independently per account

The account store SHALL hold planner records and their pending mutations independently of entries and categories. Planner mutations SHALL use the transactional outbox and existing durable deletion/undo contract. Planner records SHALL NOT feed History, Insights, or Recents. The timer draft's optional linked task ID SHALL be local, not part of any synced entry.

#### Scenario: Account switch with unsynced tasks
- **WHEN** a user switches accounts with local planner edits or a linked run pending
- **THEN** neither the tasks nor the timer draft appear or sync under the other account, and returning to the original account restores its local state

## MODIFIED Requirements

### Requirement: Timer draft holds text and live categories
The `timer_state` singleton SHALL hold `(activity_text, ordered category_ids, notes, started_at, status, optional planner task ID)` for the running draft. Toggles SHALL rewrite the snapshot in the same chokepoint transaction. Notes saves SHALL rewrite only the notes field in the same chokepoint transaction. Start-time edits SHALL rewrite only `started_at`. Stop SHALL create the entry from the draft (text + final categories + final notes + final start) and clear it. When the ID still refers to an unfinished task in the bound account, the same transaction SHALL complete that task for the local calendar date of Stop and queue its update alongside the entry create. A missing, deleted, or already-completed task SHALL NOT be created or modified by Stop. A failure SHALL leave the entry, task, and outbox unmodified and the draft retryable.

#### Scenario: Crash restores draft tags
- **WHEN** the app restarts with a persisted running draft
- **THEN** the timer resumes with the locked text and the tags as last left

#### Scenario: Crash restores draft notes
- **WHEN** the app restarts with a persisted running draft holding notes
- **THEN** the timer resumes with the draft notes as last left, and Stop saves the entry with those notes unless edited further

#### Scenario: Mid-run notes edit rewrites the snapshot
- **WHEN** the user saves notes while running
- **THEN** only the draft notes field updates in the same chokepoint transaction

#### Scenario: Mid-run start edit rewrites only the start field
- **WHEN** the user confirms a new start time while running
- **THEN** only `started_at` updates, nothing is queued for syncing the draft, and Stop still enqueues exactly one entry create

#### Scenario: Task changes while the timer runs
- **WHEN** the task is renamed or reordered after Start
- **THEN** Stop uses the draft's locked name for the entry and completes the task by ID without reverting its edit or order

#### Scenario: Stop does not restore a deleted task
- **WHEN** a linked task has been deleted by the time the timer commits its Stop
- **THEN** the original timer draft saves as an ordinary entry and the task stays deleted

#### Scenario: Failed or duplicate Stop has no extra completion
- **WHEN** a linked Stop fails and is retried, or the same committed Stop is delivered twice
- **THEN** the failed attempt leaves the task and entry unchanged, the successful attempt saves one entry and at most one completion, and replay never completes a task that the user subsequently reopened
