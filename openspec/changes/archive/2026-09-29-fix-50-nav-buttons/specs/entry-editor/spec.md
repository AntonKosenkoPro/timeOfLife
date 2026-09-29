## MODIFIED Requirements

### Requirement: Pushed entry form uses Back-plus-checkmark chrome

When the unified entry form is pushed onto the History navigation stack (`embeddedInNavigationStack`), the navigation bar SHALL show the system Back button as the sole dismissal affordance — no `Cancel` text button and no `X` button SHALL be present. EDIT mode SHALL offer a checkmark (`✓`, `checkmark` symbol) confirm action in the confirmation placement that performs the same save as today's `Save` under the same validity gate (enabled only when the trimmed name is non-empty AND end is strictly after start; otherwise disabled with no error text). LOCKED mode SHALL show Back only, with no confirm action. The confirm button SHALL keep the `EntryEditSaveButton` accessibility identifier and SHALL carry a localized VoiceOver label. Toolbar tint stays the system default.

#### Scenario: Edit mode shows Back and checkmark, no Cancel

- **WHEN** the form opens pushed for an existing `manual` entry
- **THEN** the nav bar shows the system Back button, the `Edit entry` title, and a `✓` confirm button — and no `Cancel`/`X` button

#### Scenario: Checkmark gate matches Save gate

- **WHEN** the pushed EDIT form holds an empty trimmed name or an end equal to or before the start
- **THEN** the `✓` button is disabled with no error text, exactly as `Save` was

#### Scenario: Locked pushed mode shows Back only

- **WHEN** the form opens pushed for an entry with a non-`manual` source
- **THEN** the nav bar shows the system Back button and the imported title, with no dismiss text button and no confirm action
