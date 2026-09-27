## MODIFIED Requirements

### Requirement: Availability guard for iOS 18+
The Control SHALL be offered natively on all supported OS versions. The app's deployment target SHALL be iOS 18. No `if #available(iOS 18, *)` guards SHALL remain around Control code, and there SHALL be no absent-Control branch for older OS versions.

#### Scenario: iOS 18+ device
- **WHEN** the user runs the app on iOS 18 or later
- **THEN** the Lifio Control is available to add to the lock screen / Control Center without any availability-guard branching

#### Scenario: iOS 15–17 device
- **WHEN** a device runs iOS 15, 16, or 17
- **THEN** the app cannot be installed (deployment floor is iOS 18); no Control-absent runtime branch exists
