## Purpose

Records where each time entry came from (manual, widget, Siri, lock-screen Control, Screen Time, Garmin, etc.) so the user can see entry sources and the system can prevent duplicate imports.

## ADDED Requirements

### Requirement: Entry source and source_ref fields
Every entry SHALL carry a `source` field (one of: `manual`, `widget`, `siri`, `control`, `screentime`, `garmin`, `calendar`, `healthkit`, or future additions) and an optional `source_ref` field holding the external identifier for that source (e.g., Garmin activity id, Screen Time callback uuid, `.ics` UID). The system SHALL persist these fields in the local database and propagate them through the sync outbox and relay.

#### Scenario: Manual entry
- **WHEN** the user starts a timer from the main app
- **THEN** the created entry has `source='manual'` and `source_ref` is null

#### Scenario: Widget-started entry
- **WHEN** the user taps a widget button that starts an activity via deep-link
- **THEN** the created entry has `source='widget'` and `source_ref` is null

#### Scenario: Lock-screen Control entry
- **WHEN** the user taps a lock-screen Control that starts the timer via a background App Intent
- **THEN** the created entry has `source='control'` and `source_ref` is null

#### Scenario: Screen Time entry
- **WHEN** the Screen Time extension creates an entry from a device-usage callback
- **THEN** the entry has `source='screentime'` and `source_ref` set to a stable identifier for that callback interval

### Requirement: Duplicate import prevention
The system SHALL enforce a uniqueness constraint on `(user_id, source, source_ref)` for entries with a non-null `source_ref`, so that a source re-sending the same record (e.g., Screen Time firing twice for the same interval, Garmin re-syncing) does not create a duplicate.

#### Scenario: Screen Time duplicate callback
- **WHEN** the Screen Time extension fires twice for the same device-usage interval and attempts to create two entries with the same `(source='screentime', source_ref=<interval-id>)`
- **THEN** the second insert is rejected by the uniqueness constraint; no duplicate entry is created

#### Scenario: Garmin re-sync
- **WHEN** the integration hub re-imports a Garmin activity that was already imported (same `source_ref`)
- **THEN** the uniqueness constraint prevents a duplicate; the existing entry is kept as-is

### Requirement: Delete does not resurrect on re-import
When the user deletes an imported entry and the window elapses, the deletion SHALL commit to the outbox and propagate to the relay. A subsequent re-import of the same `(source, source_ref)` SHALL NOT resurrect the entry, because the relay's delete is hard and the uniqueness constraint rejects re-creation of the same id.

#### Scenario: Delete then re-import
- **WHEN** the user deletes a Garmin-imported entry, the undo window elapses, the deletion syncs to the relay, and the Garmin connector re-sends the same activity
- **THEN** the relay has no record to update and the re-import attempt either no-ops (the connector checks existing) or is rejected; the entry is not resurrected

### Requirement: User-visible source labels
The system SHALL display the provenance of an entry to the user (e.g., "via Screen Time", "via Garmin", "via Widget") in the entry detail and history views, using localized strings. Entries with `source='manual'` SHALL display no source label (they are the default).

#### Scenario: Screen Time entry shown with label
- **WHEN** the user views a history entry with `source='screentime'`
- **THEN** the entry detail shows a localized "via Screen Time" label (EN and RU)

#### Scenario: Manual entry shows no label
- **WHEN** the user views a history entry with `source='manual'`
- **THEN** no source label is displayed