## ADDED Requirements

### Requirement: History rows indicate entries with notes

Each History row SHALL show a small blue notes icon when the entry's notes are non-empty and SHALL show no icon otherwise. Whitespace-only notes count as empty. The icon is purely presentational: it changes no tap, swipe, long-press, or navigation behavior, and the row's VoiceOver label folds in a localized "has notes" affordance when the icon is shown.

#### Scenario: Row with notes shows the icon
- **WHEN** an entry has non-empty notes
- **THEN** its History row shows the small blue notes icon at the fixed position defined in design.md

#### Scenario: Row without notes shows no icon
- **WHEN** an entry has empty notes
- **THEN** its History row renders exactly as today, with no icon and no layout shift beyond the icon's absence

#### Scenario: Whitespace-only notes count as empty
- **WHEN** an entry's notes contain only whitespace or newlines
- **THEN** its History row shows no notes icon

#### Scenario: Icon does not change row interaction
- **WHEN** the user taps a History row that shows the notes icon
- **THEN** the unified entry form opens for that entry, exactly as for rows without the icon

#### Scenario: VoiceOver announces notes presence
- **WHEN** VoiceOver reads a History row whose entry has non-empty notes
- **THEN** the row label includes the localized "has notes" affordance alongside the existing text, duration, categories, and timeframe
