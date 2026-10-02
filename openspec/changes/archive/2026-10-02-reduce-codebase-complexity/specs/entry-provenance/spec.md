## MODIFIED Requirements

### Requirement: Entry source and source_ref fields
Every entry SHALL carry a `source` field (one of: `manual`, `widget`, `siri`, `control`, `screentime`, `garmin`, `calendar`, `healthkit`, or future additions) and an optional `source_ref` field holding the external identifier for that source (e.g., Garmin entry id, Screen Time callback uuid, `.ics` UID). The system SHALL persist these fields in the local database and propagate them through the sync outbox and relay. There is no activity entity — sources create entries, never activities.

#### Scenario: Manual entry
- **WHEN** the user starts a timer from the main app
- **THEN** the created entry has `source='manual'` and `source_ref` is null

#### Scenario: Widget-started entry
- **WHEN** the user taps a widget button that starts the timer via deep-link
- **THEN** the created entry has `source='widget'` and `source_ref` is null

#### Scenario: Lock-screen Control entry
- **WHEN** the user taps a lock-screen Control that starts the timer via a background App Intent
- **THEN** the created entry has `source='control'` and `source_ref` is null

#### Scenario: Screen Time entry
- **WHEN** the Screen Time extension creates an entry from a device-usage callback
- **THEN** the entry has `source='screentime'` and `source_ref` set to a stable identifier for that callback interval
