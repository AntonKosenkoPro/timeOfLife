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
The app SHALL expose account, sync, category management, and destructive data controls from a profile destination rather than as a primary tab. The profile destination SHALL NOT expose integrations, export, appearance, or data-and-privacy placeholder rows. Activity management SHALL NOT appear in Profile (no activity catalog exists). The Profile "Enable Sync" action SHALL first attempt a silent session restore; when the session is still signed out afterward, it SHALL present the auth flow (`AuthFlowView`) as a sheet framed as optional cross-device sync. The sheet SHALL dismiss on successful sign-in and offer an explicit Cancel close path; dismissing unsigned SHALL return to Profile with local data untouched.

#### Scenario: Open profile while signed out
- **WHEN** a user without an account opens the profile destination
- **THEN** local configuration remains available and account sync is presented as an optional action

#### Scenario: Return from profile
- **WHEN** the user dismisses or navigates back from the profile destination
- **THEN** the previously selected primary destination and its state are restored

#### Scenario: Enable Sync with a restorable session
- **WHEN** a signed-out user with a valid Keychain session taps "Enable Sync"
- **THEN** the silent restore signs them in with no sheet shown

#### Scenario: Enable Sync without a restorable session
- **WHEN** a signed-out user with no restorable session taps "Enable Sync"
- **THEN** the auth flow sheet opens (never a silent no-op), voiced as optional cross-device sync

#### Scenario: Sign in from the sheet
- **WHEN** the user completes sign-in inside the sheet
- **THEN** the sheet dismisses and Profile shows the signed-in sync state

#### Scenario: Dismiss the sheet unsigned
- **WHEN** the user cancels the sheet without signing in
- **THEN** Profile returns unsigned with local data and the outbox untouched

#### Scenario: No placeholder rows
- **WHEN** the user opens Profile in any auth state
- **THEN** no Integrations, Export, Appearance, or Data & Privacy rows are shown, and every visible row is tappable or a live status
### Requirement: Running timer remains globally accessible
The app SHALL keep an active timer visible and directly stoppable while History or Insights is selected. The compact timer SHALL float above the tab bar with a visible gap — never overlapping or touching it.

#### Scenario: Browse while timing
- **WHEN** a timer is running and the user switches from Track to History or Insights
- **THEN** a compact timer displays the entry text and live elapsed duration without obscuring primary navigation

#### Scenario: Stop outside Track
- **WHEN** the user activates Stop on the compact timer
- **THEN** the app saves the entry with the draft's final categories, removes the compact timer, and keeps the current destination selected

#### Scenario: Return to full timer
- **WHEN** the user activates the non-destructive area of the compact timer
- **THEN** the app selects Track and presents the running numeric timer

#### Scenario: Compact timer clears the tab bar
- **WHEN** a timer is running and the user views History or Insights
- **THEN** the compact timer renders fully above the tab bar with daylight between them on every supported screen size

#### Scenario: Track settles after an external stop
- **WHEN** the user returns to Track after stopping the timer from the compact timer
- **THEN** Track shows the settled post-stop state for the same text — never a running timer counting from the stopped start time
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
