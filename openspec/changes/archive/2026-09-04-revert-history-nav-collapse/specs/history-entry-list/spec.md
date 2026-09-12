## MODIFIED Requirements

### Requirement: History preserves compact timer access with a persistent nav bar
The History destination SHALL keep the compact cross-tab running timer visible and stoppable, matching the app-shell "Running timer remains globally accessible" requirement. The History destination SHALL keep the navigation bar (inline "History" title and Profile button) permanently visible while History is on screen, regardless of list scroll position. The Profile button is reachable at all times on History.

#### Scenario: Compact timer on History
- **WHEN** a timer is running and the user selects History
- **THEN** the compact timer is visible at the bottom safe area and the entry list scrolls above it

#### Scenario: Navigation bar always visible
- **WHEN** the user scrolls the History list down and back up
- **THEN** the inline "History" title and Profile button remain visible at every scroll position