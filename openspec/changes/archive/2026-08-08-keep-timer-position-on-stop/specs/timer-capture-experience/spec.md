## MODIFIED Requirements

### Requirement: Timer states remain visually and physically stable
The idle, ready, running, saving, saved, and error states SHALL preserve the numeric timer's position and primary control geometry, support light and dark appearance, respect Reduce Motion, and expose accessible state. Transient saved-state feedback displayed above the numeric timer SHALL NOT change the timer's vertical position.

#### Scenario: State transition
- **WHEN** Track changes between ready, running, and saved states
- **THEN** content transitions without moving the numeric timer or primary action to a different interaction region

#### Scenario: Saved confirmation appears
- **WHEN** a successful stop displays the saved-state confirmation mark above the numeric timer
- **THEN** the mark appears without changing the numeric timer's vertical position

#### Scenario: Reduce Motion enabled
- **WHEN** Reduce Motion is enabled
- **THEN** state changes use restrained fades or immediate updates instead of rotational or spring-based animation

#### Scenario: VoiceOver reads numeric timer
- **WHEN** VoiceOver focuses the numeric timer
- **THEN** it announces the selected Activity, timer state, elapsed duration, and the available primary action
