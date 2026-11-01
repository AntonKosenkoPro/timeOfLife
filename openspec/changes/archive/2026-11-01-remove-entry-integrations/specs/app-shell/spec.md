## ADDED Requirements

### Requirement: Minimum supported iOS version
The app and its Live Activity targets SHALL require iOS 18 or later. Removing Controls SHALL NOT lower the deployment floor or introduce runtime support branches for iOS 15–17. Availability branches for features introduced after iOS 18 remain permitted.

#### Scenario: iOS 18 or later
- **WHEN** a user runs the app on iOS 18 or later
- **THEN** the app runs with its native supported feature set without an iOS-18 availability fallback; the abandoned Control is not offered

#### Scenario: Older iOS device
- **WHEN** a device runs iOS 15, 16, or 17
- **THEN** the app cannot be installed because its minimum deployment target remains iOS 18
