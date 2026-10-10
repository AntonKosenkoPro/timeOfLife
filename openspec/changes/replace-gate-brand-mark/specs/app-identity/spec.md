## ADDED Requirements

### Requirement: Welcome screen shows the Lifio brand mark
The system SHALL render the Lifio product glyph (`^▬` brand mark, `BrandMark` asset) above the "Lifio" brand title on the Welcome screen, in place of the generic timer symbol. The mark SHALL be single-color in the accent voice, identical in shape and size to the restoring splash mark, and hidden from VoiceOver as decorative.

#### Scenario: Welcome brand mark in English
- **WHEN** a signed-out user opens the Welcome screen with the device locale set to English
- **THEN** the product glyph renders above the "Lifio" title in the accent color

#### Scenario: Welcome brand mark in Russian
- **WHEN** a signed-out user opens the Welcome screen with the device locale set to Russian
- **THEN** the product glyph renders above the "Lifio" title exactly as in English (mark is locale-invariant)

#### Scenario: Mark is decorative for assistive technology
- **WHEN** VoiceOver focuses the Welcome-screen brand region
- **THEN** the mark itself is skipped and the "Lifio" title remains announced
