# App Shell Specification

## Purpose

Defines a stable product hierarchy for frequent capture, retrospective review, and analysis while keeping account and configuration tasks secondary and preserving access to a running timer.

## Requirements

### Requirement: Three primary destinations
The app SHALL provide Track, History, and Insights as its primary destinations, and SHALL identify Track as the destination for starting and controlling a timer. The History destination SHALL present committed time entries as a day-grouped, read-only list (see `history-entry-list` capability). The Insights destination SHALL present a period-scoped breakdown of committed tracked time with a hero total (see `insights-breakdown` capability), replacing the empty-state placeholder whenever committed entries exist. The History destination SHALL show the navigation bar (inline title and Profile button) at rest and collapse it on scroll; the Profile button remains present on Track and Insights.

#### Scenario: Local launch
- **WHEN** the user launches the app without an account or active timer
- **THEN** the app opens Track and provides access to History and Insights without requiring authentication

#### Scenario: Switching destinations
- **WHEN** the user selects History or Insights
- **THEN** the selected destination becomes visible without changing timer state or discarding the state of the previous destination

#### Scenario: Profile access on History
- **WHEN** the user is on History at rest (list at top) and wants to open Profile
- **THEN** the Profile button is visible in the navigation bar and opens Profile

#### Scenario: Insights shows breakdown
- **WHEN** the user selects Insights with committed entries on record
- **THEN** the period breakdown with hero total is shown instead of the empty-state placeholder

### Requirement: Profile owns secondary destinations
The app SHALL expose account, sync, activity and category management, integrations, export, appearance, and destructive data controls from a profile destination rather than as a primary tab.

#### Scenario: Open profile while signed out
- **WHEN** a user without an account opens the profile destination
- **THEN** local configuration remains available and account sync is presented as an optional action

#### Scenario: Return from profile
- **WHEN** the user dismisses or navigates back from the profile destination
- **THEN** the previously selected primary destination and its state are restored

### Requirement: Running timer remains globally accessible
The app SHALL keep an active timer visible and directly stoppable while History or Insights is selected.

#### Scenario: Browse while timing
- **WHEN** a timer is running and the user switches from Track to History or Insights
- **THEN** a compact timer displays the activity and live elapsed duration without obscuring primary navigation

#### Scenario: Stop outside Track
- **WHEN** the user activates Stop on the compact timer
- **THEN** the app saves the entry, removes the compact timer, and keeps the current destination selected

#### Scenario: Return to full timer
- **WHEN** the user activates the non-destructive area of the compact timer
- **THEN** the app selects Track and presents the running numeric timer

### Requirement: Navigation is accessible and stateful
Primary navigation and the compact timer SHALL expose stable accessibility labels, values, hints, and identifiers, and SHALL remain operable with VoiceOver and Dynamic Type.

#### Scenario: VoiceOver reads active timer
- **WHEN** VoiceOver focuses the compact timer
- **THEN** it announces the activity name, elapsed duration, running state, and available actions

#### Scenario: Large text
- **WHEN** the user selects an accessibility Dynamic Type size
- **THEN** navigation labels and compact timer content remain readable without hiding Start or Stop actions

### Requirement: Product hierarchy transfers to macOS
The product SHALL preserve Track, History, Insights, and profile-owned secondary destinations when represented in a macOS navigation container.

#### Scenario: macOS hierarchy
- **WHEN** the product hierarchy is implemented on macOS
- **THEN** Track, History, and Insights appear as primary sidebar destinations and profile-owned features remain secondary without changing their meaning
