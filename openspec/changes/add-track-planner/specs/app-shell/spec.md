## ADDED Requirements

### Requirement: Track toolbar opens the planner
The Track root SHALL expose an accessible planner button in its top toolbar alongside Profile. It SHALL present the planner sheet without adding a navigation-path entry, a primary tab, or a planner button to History/Insights. The button SHALL remain available during a run for checklist management, but SHALL NOT displace an existing modal or act before the account's Track state is ready.

#### Scenario: Open from running Track
- **WHEN** Track is ready with a running timer and the user taps the planner button
- **THEN** the planner sheet opens for checklist management while the running timer continues unchanged

#### Scenario: Close returns to Track
- **WHEN** the planner sheet is dismissed
- **THEN** the user remains on the same Track navigation root with the existing Profile destination and tab structure unchanged
