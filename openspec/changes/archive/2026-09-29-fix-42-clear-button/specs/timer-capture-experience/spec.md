## MODIFIED Requirements

### Requirement: Track name clear shows only when focused and non-empty, Apple-standard look

The Track name field's trailing clear (`×`) button SHALL be visible only when the field is focused AND holds non-empty text (idle/ready/saved states; never while running — the name is locked then). One tap SHALL clear the draft and return Track to idle. The button SHALL use the Apple-standard trailing look: a small (17 pt) dim `xmark.circle.fill` in system secondary gray tucked at the field's trailing edge, with the 44 pt accessible tap target preserved.

#### Scenario: Clear hidden when unfocused, even with text

- **WHEN** the Track name field holds text but is not focused
- **THEN** no clear button is shown

#### Scenario: Clear hidden when empty, even when focused

- **WHEN** the Track name field is focused but empty
- **THEN** no clear button is shown

#### Scenario: Clear visible when focused with text

- **WHEN** the Track name field is focused and holds text while idle, ready, or saved
- **THEN** a small dim trailing `×` is visible, and one tap empties the field and returns Track to idle

#### Scenario: No clear button while running

- **WHEN** a timer is running
- **THEN** the name is locked and no clear button is shown
