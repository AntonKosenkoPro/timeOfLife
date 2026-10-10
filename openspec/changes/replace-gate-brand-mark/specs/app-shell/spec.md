## ADDED Requirements

### Requirement: Restoring splash shows the Lifio brand mark
The restoring splash SHALL render the Lifio product glyph (`^▬` brand mark, `BrandMark` asset) above the app name, in place of the generic timer symbol — the same mark, tint, and size as the Welcome screen, so the restore→auth transition keeps one continuous brand. The mark SHALL be hidden from VoiceOver as decorative. Background continuity with the OS launch screen (plain background color, no image) is unchanged.

#### Scenario: Restoring session shows brand mark, not login
- **WHEN** the app launches with a cached session whose server validation is still in flight
- **THEN** the gate renders the restoring splash with the product glyph above the app name and a spinner, never the auth flow

#### Scenario: Splash mark matches Welcome mark
- **WHEN** the restore resolves to signed-out and the auth flow replaces the splash
- **THEN** the Welcome screen shows the same glyph at the same size and tint, with no visible mark switch beyond the screen transition

#### Scenario: Splash mark is decorative for assistive technology
- **WHEN** VoiceOver focuses the restoring splash
- **THEN** the mark itself is skipped and the existing `RestoringSplash` identifier keeps working
