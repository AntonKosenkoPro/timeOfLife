## MODIFIED Requirements

### Requirement: Availability guard for iOS 18+
The Control SHALL be available only on iOS 18+ and SHALL be absent (no Control offered) on iOS 15–17. The app's deployment target SHALL remain iOS 15. The Control code SHALL be wrapped in `if #available(iOS 18, *)` guards so the app builds and runs on iOS 15+.

#### Scenario: iOS 18+ device
- **WHEN** the user runs the app on iOS 18 or later
- **THEN** the Lifio Control is available to add to the lock screen / Control Center

#### Scenario: iOS 15–17 device
- **WHEN** the user runs the app on iOS 15, 16, or 17
- **THEN** no Control is offered; the app's other features work normally
