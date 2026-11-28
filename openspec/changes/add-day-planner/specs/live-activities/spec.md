## ADDED Requirements

### Requirement: Live Activity Stop completes the linked planned task

The existing Live Activity Stop link SHALL use the same account-bound Stop transaction and feedback as Track for planner-linked runs, including a cold open. The extension SHALL NOT write planner data or acquire a new task control. Notes review SHALL NOT repeat task completion.

#### Scenario: Cold-open Stop for a linked run
- **WHEN** the user taps Stop from the Island or Lock Screen banner with a persisted planner-linked run and the app is terminated
- **THEN** the app restores the bound draft, saves the entry and completes the linked unfinished task once, and the activity shows the ordinary Saved card
