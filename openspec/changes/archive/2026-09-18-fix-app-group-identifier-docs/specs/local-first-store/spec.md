## MODIFIED Requirements

### Requirement: App Group shared container
The system SHALL store the local database in an App Group shared container (`group.com.antonkosenko.timeoflifeapp`) so that the main app, widget extensions, Screen Time extension, and lock-screen Control intents can read and write the same data cross-process.

#### Scenario: Widget reads catalog
- **WHEN** a home-screen widget renders and reads the activities table from the shared container
- **THEN** it sees the same records the main app wrote, without a separate copy or IPC handshake

#### Scenario: Extension writes entry
- **WHEN** the Screen Time extension writes an entry to the shared container database
- **THEN** the main app observes that entry on its next foreground, without an explicit IPC call
