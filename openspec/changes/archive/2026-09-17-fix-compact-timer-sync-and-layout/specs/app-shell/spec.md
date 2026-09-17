# App Shell — Compact Stop & Spacing Delta

## MODIFIED Requirements

### Requirement: Running timer remains globally accessible
The app SHALL keep an active timer visible and directly stoppable while History or Insights is selected. The compact timer SHALL float above the tab bar with a visible gap — never overlapping or touching it.

#### Scenario: Browse while timing
- **WHEN** a timer is running and the user switches from Track to History or Insights
- **THEN** a compact timer displays the activity and live elapsed duration without obscuring primary navigation

#### Scenario: Stop outside Track
- **WHEN** the user activates Stop on the compact timer
- **THEN** the app saves the entry, removes the compact timer, and keeps the current destination selected

#### Scenario: Return to full timer
- **WHEN** the user activates the non-destructive area of the compact timer
- **THEN** the app selects Track and presents the running numeric timer

#### Scenario: Compact timer clears the tab bar
- **WHEN** a timer is running and the user views History or Insights
- **THEN** the compact timer renders fully above the tab bar with daylight between them on every supported screen size

#### Scenario: Track settles after an external stop
- **WHEN** the user returns to Track after stopping the timer from the compact timer
- **THEN** Track shows the settled post-stop state for the same activity — never a running timer counting from the stopped start time
