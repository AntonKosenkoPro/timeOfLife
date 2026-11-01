## REMOVED Requirements

### Requirement: Running timer remains globally accessible
**Reason**: The compact timer is removed to keep History and Insights focused on browsing. Persistent in-app off-Track visibility and direct Stop are no longer product requirements.
**Migration**: Select Track to view or stop a running timer. Existing Live Activity Stop and return actions remain available where enabled and supported; they are not a prerequisite for tracking. External-stop reconciliation remains required by `timer-capture-experience`.

## ADDED Requirements

### Requirement: History and Insights have no in-app running-timer surface
While History or Insights is selected, the app SHALL NOT render an in-app compact timer, replacement timer strip, running badge or indicator, toolbar timer, or off-Track Stop action. It SHALL NOT reserve space for the removed timer or offer a preference to restore it. Selecting Track SHALL present the current persisted run through the existing Track experience. Tab navigation SHALL NOT stop, restart, or alter the running timer.

#### Scenario: Browse while timing without extra chrome
- **WHEN** a timer is running and the user selects History or Insights
- **THEN** that destination has no in-app running-timer surface or timer-only reserved space, while its ordinary content and navigation remain available

#### Scenario: Return to Track to stop
- **WHEN** the user selects Track after browsing History or Insights during a run
- **THEN** Track shows the same running timer with its original start anchor and current draft values, and its existing Stop action remains available

#### Scenario: No dependence on system timer visibility
- **WHEN** Live Activities are disabled or the device has no Dynamic Island and the user browses History or Insights during a run
- **THEN** the same timer-free in-app layout is used and selecting Track still provides the running timer and Stop action

#### Scenario: No restoration setting
- **WHEN** the user opens Profile or its settings destinations
- **THEN** no preference to restore the removed compact timer or enable a replacement running indicator is offered

## MODIFIED Requirements

### Requirement: Navigation is accessible and stateful
Primary navigation SHALL expose stable accessibility labels, values, hints, and identifiers, and SHALL remain operable with VoiceOver and Dynamic Type. Removing the compact timer SHALL NOT remove accessibility support for Track's timer or the existing Live Activity surfaces.

#### Scenario: VoiceOver navigates to Track
- **WHEN** VoiceOver focuses the Track tab from History or Insights
- **THEN** it announces the localized tab label and selection state, and activating the tab opens Track with its existing accessible timer controls

#### Scenario: VoiceOver reads active timer
- **WHEN** the user returns to Track from History or Insights and VoiceOver focuses the active timer
- **THEN** Track's existing accessible timer exposes its name, elapsed duration, running state, and available controls without requiring a compact timer on the previous destination

#### Scenario: Large text
- **WHEN** the user selects an accessibility Dynamic Type size
- **THEN** primary navigation remains readable and operable, and Track's existing Start and Stop actions remain accessible
