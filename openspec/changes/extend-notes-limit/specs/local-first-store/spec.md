## MODIFIED Requirements

### Requirement: Entries own text, categories, and notes
Each entry SHALL own its `activity_text` (trimmed, non-empty, max 60 chars; case-sensitive identity), its ordered `category_ids` (zero or more, position-preserved via `entry_categories`), and its `notes` (max 2000 trimmed runes, default empty). No entry SHALL reference any other record for its display name or classification.

#### Scenario: Entry saved with all fields
- **WHEN** a valid entry is saved with text, two ordered categories, and notes
- **THEN** all three persist on the entry and read back identically

#### Scenario: Per-entry isolation
- **WHEN** one entry's text, categories, or notes change
- **THEN** no other entry changes

#### Scenario: Notes past the bound are rejected
- **WHEN** an entry holds more than 2000 trimmed runes of notes
- **THEN** the relay rejects the create/update with a notes `validation_error` and the local entry is unchanged
