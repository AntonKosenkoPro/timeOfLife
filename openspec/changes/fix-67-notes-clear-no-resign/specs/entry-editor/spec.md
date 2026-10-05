## ADDED Requirements

### Requirement: Notes clear never dismisses the keyboard

Tapping the Notes-row clear (`×`) SHALL clear the field and keep the keyboard open with no dismiss/reappear transition. Taps on the card's labels, padding, and background SHALL still resign focus, and taps on the name row, category chips, and start/end pills SHALL still resign focus.

#### Scenario: Clear notes with keyboard open
- **WHEN** the Notes field is focused with non-empty text and the user taps `×`
- **THEN** the field empties, the keyboard stays open and focused, and no dismiss animation plays

#### Scenario: Tap-away still dismisses
- **WHEN** the user taps a card label, padding, or background
- **THEN** the keyboard dismisses as before

#### Scenario: Control taps still dismiss
- **WHEN** the user taps the name row, a category chip, or a start/end pill
- **THEN** the tapped control acts and the keyboard dismisses as before
