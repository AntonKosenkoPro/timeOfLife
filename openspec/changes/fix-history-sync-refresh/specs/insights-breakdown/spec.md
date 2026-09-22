## ADDED Requirements

### Requirement: Insights reflects synced changes without re-entry
The Insights destination SHALL recompute its breakdown when a sync cycle completes while Insights is visible, including a manual Sync now triggered from the Profile sheet opened over Insights. Pulled entries, category changes, and tombstone deletions SHALL appear in the hero total and rows without requiring the user to leave and re-enter the tab.

#### Scenario: Sync now from Profile over Insights
- **WHEN** the user opens Profile from the Insights tab, taps Sync now, the cycle pulls cross-device changes, and dismisses Profile
- **THEN** the hero total and breakdown rows reflect the pulled state without any tab switch

#### Scenario: Automatic sync while Insights is visible
- **WHEN** a foreground or connectivity-restored sync cycle merges relay changes while Insights is on screen
- **THEN** the breakdown reloads to reflect the merged state once the cycle completes
