## MODIFIED Requirements

### Requirement: Availability guard for iOS 18+
The app's deployment target SHALL be iOS 18. No `if #available(iOS 18, *)` guards SHALL exist around Control code. The Control target itself remains deferred (no widget target in `project.yml`); the start/stop, authentication, failure, state-reading, and outbox requirements stay in force as the contract for its future implementation.

#### Scenario: iOS 18+ device
- **WHEN** the user runs the app on iOS 18 or later
- **THEN** the app runs natively with no availability-guard branching; the lock-screen Control is not yet offered (deferred)

#### Scenario: iOS 15–17 device
- **WHEN** a device runs iOS 15, 16, or 17
- **THEN** the app cannot be installed (deployment floor is iOS 18); no Control-absent runtime branch exists
