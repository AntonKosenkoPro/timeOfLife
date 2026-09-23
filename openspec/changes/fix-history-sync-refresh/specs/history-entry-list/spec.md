## ADDED Requirements

### Requirement: History reflects synced changes without re-entry
The History destination SHALL reload its day groups when a sync cycle completes while History is visible, including a manual Sync now triggered from the Profile sheet opened over History. Pulled entries, category changes, and tombstone deletions SHALL appear without requiring the user to leave and re-enter the tab.

#### Scenario: Sync now from Profile over History
- **WHEN** the user opens Profile from the History tab, taps Sync now, the cycle pulls cross-device changes, and dismisses Profile
- **THEN** the History list shows the pulled entries and deletions in their day groups without any tab switch

#### Scenario: Automatic sync while History is visible
- **WHEN** a foreground or connectivity-restored sync cycle merges relay changes while History is on screen
- **THEN** the History list reloads to reflect the merged state once the cycle completes

#### Scenario: Failed sync keeps current list
- **WHEN** a sync cycle fails with an offline or transport error having applied no merges
- **THEN** the History list keeps its current content and reports no spurious empty state
