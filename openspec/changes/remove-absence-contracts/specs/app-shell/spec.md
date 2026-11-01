## REMOVED Requirements

### Requirement: History and Insights have no in-app running-timer surface
**Reason**: Absence contract for a removed feature — it enumerates alternatives that never existed (replacement strip, badge, toolbar timer, restore preference) instead of stating behavior.
**Migration**: The positive residue is already covered elsewhere: Track presents the run through the existing Track experience (`timer-capture-experience`), and tab navigation leaving the timer untouched is ordinary behavior with no requirement of its own.

## MODIFIED Requirements

### Requirement: Navigation is accessible and stateful
Primary navigation SHALL expose stable accessibility labels, values, hints, and identifiers, and SHALL remain operable with VoiceOver and Dynamic Type. Accessibility support for Track's timer and the existing Live Activity surfaces is unchanged.

#### Scenario: VoiceOver navigates to Track
- **WHEN** VoiceOver focuses the Track tab from History or Insights
- **THEN** it announces the localized tab label and selection state, and activating the tab opens Track with its existing accessible timer controls

#### Scenario: VoiceOver reads active timer
- **WHEN** the user returns to Track from History or Insights and VoiceOver focuses the active timer
- **THEN** Track's existing accessible timer exposes its name, elapsed duration, running state, and available controls

#### Scenario: Large text
- **WHEN** the user selects an accessibility Dynamic Type size
- **THEN** primary navigation remains readable and operable, and Track's existing Start and Stop actions remain accessible
