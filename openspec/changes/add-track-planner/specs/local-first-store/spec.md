## MODIFIED Requirements

### Requirement: Transactional outbox
The system SHALL record each local create/update/delete of relayed category or entry data as a row in a transactional `outbox` table, written in the same database transaction as the state change, subject to the existing durable-undo deletion staging contract. The outbox is the durable queue of operations to propagate to the backend relay when sync is active. Local-only planner task creation, completion changes, removal, and day cleanup SHALL NOT enqueue relay operations; the running timer draft remains local-only until Stop commits an entry.

#### Scenario: Create writes state and outbox atomically
- **WHEN** the user creates a committed entry or category
- **THEN** the system writes its state and an outbox row with the matching resource and create operation in a single transaction; if either write fails, neither is committed

#### Scenario: Delete is first-class in the outbox
- **WHEN** an entry/category deletion leaves the durable undo buffer through cold-launch commit
- **THEN** the system inserts the corresponding outbox delete row and removes the buffer row atomically; the outbox row persists even though the record is gone, while successful push-then-commit retains its existing no-duplicate-delete behavior

#### Scenario: Outbox survives relaunch
- **WHEN** the app is killed and relaunched with pending outbox rows
- **THEN** the outbox rows are still present and will be drained by the sync client when it next runs

#### Scenario: Planner mutations remain local-only
- **WHEN** the user creates, checks, unchecks, or removes a planner task, or prior-day completed tasks are cleaned up
- **THEN** only planner state changes and the outbox, entry/category undo buffer, sync cursors, and relay state remain unchanged
