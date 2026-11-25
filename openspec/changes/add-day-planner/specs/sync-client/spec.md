## ADDED Requirements

### Requirement: Planner records converge across devices

Planner sync SHALL be account-scoped and propagate additions, renames, ordering, completion, reopening, and deletes at task granularity. Changes to different tasks or different fields of the same task SHALL NOT discard each other. Conflicting edits to the same field SHALL converge in relay acceptance order, retries SHALL NOT reapply an acknowledged operation, and order ties SHALL resolve identically on every device. Planner deletes SHALL win over pending changes and SHALL NOT use entry/category push-404 resurrection. The planner's resumable feed SHALL include removals and completed tasks, not just the portion visible in Today, and SHALL NOT change entry/category sync behavior.

#### Scenario: Independent offline edits survive
- **WHEN** two devices add tasks offline or one renames a task while another reorders or completes it
- **THEN** after syncing both devices have both additions and the accepted changes to each independent field in the same order

#### Scenario: Delete wins even if Stop happens offline
- **WHEN** one device deletes a task and another saves a linked run against its stale local copy before syncing
- **THEN** the entry syncs normally, the task converges to deleted, and its pending completion does not recreate it

#### Scenario: A partial pull can resume without gaps
- **WHEN** a planner pull stops after a committed page and new planner changes arrive before its next page or cycle
- **THEN** the planner resumes without permanently skipping any change, and repeated pages or push retries do not duplicate tasks or undo newer changes
