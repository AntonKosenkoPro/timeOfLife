## MODIFIED Requirements

### Requirement: Relay wire-format date decoding
The client SHALL decode every relay timestamp as RFC 3339 (`format: date-time`) through dedicated wire shapes, never through the local models' timestamp decoding. Categories and entries each have their own wire decoding for `created_at`/`updated_at`. A decoding failure SHALL surface as a normal cycle error, never a stuck "Syncing…".

#### Scenario: Non-empty pull decodes
- **WHEN** the relay returns categories or entries with RFC 3339 timestamps (with or without fractional seconds)
- **THEN** the pull merges them and the cycle completes; no `typeMismatch` on `created_at`/`updated_at`
