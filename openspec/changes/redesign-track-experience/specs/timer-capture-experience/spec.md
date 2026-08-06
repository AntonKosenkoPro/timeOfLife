## Purpose

Defines a focused, local-first timer capture journey in which a centered numeric timer communicates exact actionable timer state and every start follows an explicit Activity selection.

## ADDED Requirements

### Requirement: Numeric timer is an instrumental readout
The Track numeric timer SHALL represent only timer readiness and exact elapsed timing; it SHALL NOT display fabricated progress, daily totals, goals, rings, sweeps, or history while idle.

#### Scenario: Nothing selected
- **WHEN** no activity is selected and no timer is running
- **THEN** the numeric timer presents `00:00` and a clear action to choose an Activity

#### Scenario: Activity prepared
- **WHEN** the user selects or creates an activity
- **THEN** the numeric timer presents that Activity in a ready state with an explicit Start action and zero elapsed duration

#### Scenario: Timer running
- **WHEN** the user starts the prepared activity
- **THEN** the numeric timer displays the exact live elapsed duration, including completed hours, without a secondary progress visualization

### Requirement: Starting always requires explicit confirmation
Selecting a recent, searched, or newly created Activity SHALL prepare it without starting a timer; the timer SHALL begin only after the user activates Start.

#### Scenario: Select recent activity
- **WHEN** the user taps a recent activity
- **THEN** the app selects it, closes the chooser if presented, and shows the ready numeric timer without creating an entry

#### Scenario: Start selected activity
- **WHEN** an activity is prepared and the user activates Start
- **THEN** the app persists the running timer immediately, begins elapsed-time presentation, and emits a subtle selection haptic

### Requirement: Activity chooser supports selection and creation
Track SHALL provide a chooser that supports recent Activity names, search, creation from unmatched input, and navigation to Activity management without requiring network access. The chooser SHALL NOT require or display Category metadata for capture.

#### Scenario: Choose a recent activity
- **WHEN** the chooser opens with existing activities
- **THEN** it presents recent Activity names in recency order and permits selection with one activation

#### Scenario: Search existing activities
- **WHEN** the user enters a case-insensitive query matching existing activities
- **THEN** the chooser presents the matching Activities without creating duplicates

#### Scenario: Create an unmatched activity
- **WHEN** the entered name has no case-insensitive match and passes validation
- **THEN** the chooser offers to create that name locally and prepares the created activity after confirmation

#### Scenario: Empty catalog
- **WHEN** the chooser opens with no activities
- **THEN** it explains the empty state and makes creating the first Activity the primary action

### Requirement: Categories remain optional and separate from capture
The app SHALL treat Categories as optional, zero-or-more metadata on an Activity. Category management SHALL have its own surface, and an Activity created from capture SHALL be valid without Categories. Existing entries SHALL resolve the Activity's current Categories at query time.

#### Scenario: Create without categories
- **WHEN** the user creates an unmatched Activity from the Track chooser
- **THEN** the Activity is prepared and can start with no Categories assigned

#### Scenario: Assign categories later
- **WHEN** the user opens the full Activity Editor
- **THEN** the user may assign or remove zero or more Categories without making any Category required for timing

#### Scenario: Reclassify history
- **WHEN** the user changes an Activity's Categories
- **THEN** existing entries for that Activity use the updated Category set in Insights

### Requirement: Stop saves with stable feedback
Stopping a running timer SHALL save the completed entry locally, communicate success without a blocking loader, and retain the activity in the ready state for an optional later restart.

#### Scenario: Successful stop
- **WHEN** the user activates Stop on a running timer
- **THEN** the app persists the completed entry, clears running state, emits a success haptic, briefly confirms the saved duration, and returns to the ready numeric timer for the same Activity

#### Scenario: Save failure
- **WHEN** the local store cannot save the completed entry
- **THEN** the app preserves recoverable running state and presents a localized non-field error without silently losing elapsed time

### Requirement: First use is contextual
The app SHALL guide first-time users through their first activity and timer without a blocking onboarding carousel or an account requirement.

#### Scenario: First local launch
- **WHEN** the user reaches Track with an empty catalog
- **THEN** the idle numeric timer and supporting copy direct the user to choose and create their first Activity

#### Scenario: First entry completed
- **WHEN** the user saves their first entry
- **THEN** the app confirms the result in context and does not interrupt the capture flow with unrelated sync, integration, or subscription prompts

### Requirement: Timer states remain visually and physically stable
The idle, ready, running, saving, saved, and error states SHALL preserve the numeric timer's position and primary control geometry, support light and dark appearance, respect Reduce Motion, and expose accessible state.

#### Scenario: State transition
- **WHEN** Track changes between ready, running, and saved states
- **THEN** content transitions without moving the numeric timer or primary action to a different interaction region

#### Scenario: Reduce Motion enabled
- **WHEN** Reduce Motion is enabled
- **THEN** state changes use restrained fades or immediate updates instead of rotational or spring-based animation

#### Scenario: VoiceOver reads numeric timer
- **WHEN** VoiceOver focuses the numeric timer
- **THEN** it announces the selected Activity, timer state, elapsed duration, and the available primary action
