# Timer Capture Experience Specification

## Purpose

Defines a focused, local-first timer capture journey in which a centered numeric timer communicates exact actionable timer state and every start follows an explicit Activity selection.

## Requirements

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
Selecting a recent, searched, or newly created Activity SHALL prepare it without starting a timer; the timer SHALL begin only after the user activates Start. Temporary or unresolved search input SHALL NOT be treated as a prepared Activity.

#### Scenario: Select recent activity
- **WHEN** the user taps a recent activity
- **THEN** the app selects it and shows the ready numeric timer without creating an entry

#### Scenario: Select or create through search
- **WHEN** the user confirms an existing search result or completes Activity creation
- **THEN** the app dismisses the search presentation, prepares that Activity, and shows the ready numeric timer without starting timing

#### Scenario: Search input remains unresolved
- **WHEN** the user has entered text but has not selected an existing Activity or confirmed creation
- **THEN** the app does not enable that text to start a timer or associate it with an entry

#### Scenario: Start selected activity
- **WHEN** an activity is prepared and the user activates Start
- **THEN** the app persists the running timer immediately, begins elapsed-time presentation, and emits a subtle selection haptic

### Requirement: Activity chooser supports selection and creation
Track SHALL provide one platform-native search presentation for browsing, filtering, selecting, and quick-creating Activities without requiring network access. The presentation SHALL be a searchable sheet opened by the idle `+ Choose an activity` main action or by the Activity picker within the selected-Activity row. When an Activity is selected, the row SHALL present the Activity picker or the non-interactive Activity label as a full-width control with no editing affordance (editing placement is deferred). The operating system SHALL own search-field placement, focus, keyboard, activation animation, and cancellation affordances inside the sheet. The search content SHALL NOT display Category metadata on existing Activity results and SHALL NOT offer configured creation or open the Activity Editor before creation.

#### Scenario: Activate Activity search from idle
- **WHEN** no Activity is prepared and the user activates `+ Choose an activity`
- **THEN** the searchable sheet presents Activity-selection content with an empty, focused native search field without changing the committed timer state

#### Scenario: Activate Activity search from ready
- **WHEN** an Activity is prepared and the user activates the Activity picker
- **THEN** the searchable sheet presents Activity-selection content with the selected Activity name pre-filled and the native search field focused without changing the committed timer state

#### Scenario: Show state-specific preparation actions
- **WHEN** Track is idle
- **THEN** it presents one `+ Choose an activity` control in the stable main-action region above the bottom adaptive spacing, with no Refine action

#### Scenario: Show selected-Activity actions
- **WHEN** Track has a selected Activity
- **THEN** it presents the Activity picker or non-interactive Activity label as a full-width row below the reserved error region and above Recents, with no editing affordance on Track

#### Scenario: Browse with an empty query
- **WHEN** search is active, the query is empty, and Activities exist
- **THEN** the content area presents the complete Activity catalog in recency order and permits selection with one activation

#### Scenario: Search existing activities
- **WHEN** the user enters a query matching existing Activity names case-insensitively
- **THEN** the content area presents matching Activities in recency order without changing the committed selection

#### Scenario: Exact normalized match
- **WHEN** the trimmed query case-insensitively equals an existing Activity name
- **THEN** the existing Activity is presented as the exact result and no create action is offered for that name

#### Scenario: Unmatched valid input
- **WHEN** the trimmed query passes Activity-name validation and has no case-insensitive exact match
- **THEN** the content area offers one quick-create action for that exact name and no configured-create or Refine action

#### Scenario: Quick-create an unmatched activity
- **WHEN** the user confirms quick creation for an unmatched valid name
- **THEN** the app creates the Activity locally without notes or Categories, dismisses the search presentation, and prepares it

#### Scenario: Invalid creation input
- **WHEN** the trimmed query is empty or violates Activity-name validation
- **THEN** no create action is enabled and a localized validation explanation is available without preventing search of existing Activities

#### Scenario: Dismiss the search presentation
- **WHEN** the user activates the native search cancellation affordance or dismisses the sheet without confirming
- **THEN** the search presentation ends and Track restores the Activity that was prepared before search, or idle state if none was prepared

### Requirement: Track uses an adaptive two-ended vertical layout
Track SHALL arrange its content in this top-to-bottom order: navigation title, top adaptive spacing, completion mark region, timer numbers, timer status, reserved non-field-error region, central separator, Activity search/refine row when applicable, the state-specific main action, Recents when applicable, bottom adaptive spacing, and the tab bar. The top and bottom adaptive spacing regions SHALL use one shared maximum height selected through approved layout spikes, SHALL resolve to equal heights from the remaining space, SHALL shrink toward zero when vertical space is constrained, and SHALL yield before content clips, overlaps, or becomes unreachable. Free space beyond twice the shared maximum SHALL go to the central separator between the error region and the search/refine flow. Placing the main action above Recents SHALL keep the Choose Activity, Start, and Stop controls reachable without scrolling. The local-first Track screen SHALL NOT display an offline hint.

#### Scenario: Roomy screen uses the approved spacing cap
- **WHEN** Track appears on a screen with more free space than twice the approved shared maximum
- **THEN** the top and bottom adaptive spacing regions each hold at the shared maximum and the remaining space sits in the central separator between the error region and the search/refine flow, preserving the required content order

#### Scenario: Moderate free space splits evenly
- **WHEN** Track appears on a screen whose free space is positive but at most twice the approved shared maximum
- **THEN** the free space is distributed evenly between the top and bottom adaptive spacing regions and the central separator is zero

#### Scenario: Compact height collapses adaptive spacing
- **WHEN** the visible content does not fit because of screen height, content, or Dynamic Type
- **THEN** the adaptive spacing regions and the central separator shrink toward zero before any content clips, overlaps the tab bar, or becomes unreachable, and the ordered content scrolls

#### Scenario: Idle main action
- **WHEN** no Activity is prepared
- **THEN** the main-action region presents one `+ Choose an activity` control above the bottom adaptive spacing

#### Scenario: Ready main action
- **WHEN** an Activity is prepared
- **THEN** the main-action region presents a Start control in the same region the idle main action occupied

#### Scenario: Running main action
- **WHEN** a timer is running
- **THEN** the main-action region presents a Stop control with destructive styling in the same region and no offline hint

#### Scenario: Error region preserves geometry
- **WHEN** a recoverable non-field error is active and its wrapped text fits within the reserved height
- **THEN** the error appears in the reserved region immediately above the central separator without moving the timer, preparation row, Recents, or main-action regions

#### Scenario: Wrapped error text is never cut
- **WHEN** a recoverable non-field error wraps beyond the reserved height
- **THEN** the error text is shown in full, the region grows to fit it, the top adaptive spacing yields first and then the central separator, keeping the main action stationary, and scrolling begins only when both are exhausted

#### Scenario: No active error
- **WHEN** no recoverable non-field error is active
- **THEN** the error region preserves the same layout space without exposing an empty accessibility element

#### Scenario: Completion mark does not move timer content
- **WHEN** the completion mark appears or disappears during a timer-state transition
- **THEN** the timer numbers, timer status, and controls retain their positions within the ordered layout

### Requirement: Main action holds one position across states
Track SHALL present the state-specific main action in one main-action region whose frame is identical across the idle, ready, running, saving, saved, and error states. The layout SHALL reserve a fixed-height preparation-row slot in every state, absent from the accessibility tree while idle. While Recents is hidden during running and error states, its occupied height SHALL be preserved. The main action SHALL render in a fixed-height slot equal to the tallest of its state titles at the active Dynamic Type size. When a wrapped error grows the reserved error region, the top adaptive spacing SHALL yield first, then the central separator, keeping the main action stationary; scrolling SHALL begin only when both are exhausted.

#### Scenario: Preparing an Activity preserves the main-action frame
- **WHEN** an Activity is prepared while Track is idle
- **THEN** the preparation row appears in its reserved slot and the main-action frame does not change

#### Scenario: Starting timing preserves the main-action frame
- **WHEN** the user starts timing from ready
- **THEN** Recents hides while its occupied height is preserved and the main-action frame does not change

#### Scenario: Saving preserves the main-action frame
- **WHEN** the user stops and the entry is being saved
- **THEN** Recents reappears in the preserved region and the main-action frame does not change

#### Scenario: Error within the reservation preserves the main-action frame
- **WHEN** a recoverable non-field error fits within the reserved error height
- **THEN** the main-action frame does not change

#### Scenario: Wrapped error keeps the main action stationary
- **WHEN** a recoverable non-field error wraps beyond the reserved height and the top adaptive spacing and central separator can absorb the growth
- **THEN** the main-action frame does not change; only when both are exhausted does the content scroll

### Requirement: Recents present a capped wrapping chip flow
Track SHALL present its most-recently-used Activities as a wrapping chip flow below the preparation row, ordered most-recently-used first, and SHALL cap the flow at six chips. Chips SHALL wrap onto additional rows as needed and SHALL NOT require horizontal scrolling. A single tap on a chip SHALL prepare that Activity without starting timing. Recents SHALL NOT be presented while a timer is running.

#### Scenario: More Activities than the cap
- **WHEN** the user has more than six Activities
- **THEN** Recents presents the six most-recently-used Activities and omits the rest

#### Scenario: Six or fewer Activities
- **WHEN** the user has between one and six Activities
- **THEN** Recents presents all of them in most-recently-used order

#### Scenario: Chips wrap
- **WHEN** the Recents chips cannot fit on one row
- **THEN** the chips flow onto additional rows and every chip remains visible and reachable without horizontal scrolling

#### Scenario: Tap a Recents chip
- **WHEN** the user taps a Recents chip
- **THEN** the Activity is prepared, the ready numeric timer appears, and no timer starts and no entry is created

#### Scenario: Timing hides Recents
- **WHEN** a timer is running
- **THEN** Recents is not presented and its occupied height is preserved so the main action does not move

### Requirement: Recents chips show the first assigned Category icon
A Recents chip SHALL display the icon of the first Category assigned to its Activity (first by assignment position). An Activity with no Categories SHALL render its chip without an icon. Recents chips SHALL NOT display Category names. The selected-Activity row and search results SHALL remain free of Category metadata.

#### Scenario: Activity with one Category
- **WHEN** a Recents chip's Activity has exactly one assigned Category
- **THEN** the chip displays that Category's icon

#### Scenario: Activity with multiple Categories
- **WHEN** a Recents chip's Activity has two or more assigned Categories
- **THEN** the chip displays only the icon of the Category that is first by assignment position

#### Scenario: Activity without Categories
- **WHEN** a Recents chip's Activity has no assigned Categories
- **THEN** the chip renders with the Activity name and no icon, keeping the full tap target

#### Scenario: Icon cannot render on this OS
- **WHEN** the first assigned Category's icon is unavailable on the running iOS version
- **THEN** the chip falls back to the tag glyph used elsewhere for unavailable Category icons

#### Scenario: Other capture surfaces stay category-free
- **WHEN** the user browses Track search results or the selected-Activity row
- **THEN** no Category icon or name is displayed

### Requirement: Recents highlight the prepared Activity
When an Activity is prepared, its Recents chip SHALL indicate the selected state with a filled accent presentation — accent background, on-accent text, and accent border, keeping the Category icon — a visible affordance that does not rely on color alone, and assistive technologies SHALL be told that the chip is selected. No chip SHALL appear selected while Track is idle.

#### Scenario: Chip shows selection affordance
- **WHEN** the user prepares an Activity that is present in Recents
- **THEN** that Activity's chip switches to the filled accent presentation, distinct from the unselected chips, without losing its Category icon and without adding a checkmark

#### Scenario: Selection moves
- **WHEN** the user prepares a different Activity
- **THEN** the selection affordance moves to the newly prepared Activity's chip and the previous chip returns to the unselected presentation

#### Scenario: No selection while idle
- **WHEN** no Activity is prepared
- **THEN** no Recents chip displays the selection affordance

#### Scenario: VoiceOver announces the selected chip
- **WHEN** VoiceOver focuses the prepared Activity's Recents chip
- **THEN** it announces the Activity name and that the chip is selected

#### Scenario: Chips keep full tap targets
- **WHEN** a Recents chip renders with an icon, without an icon, or in the selected presentation
- **THEN** its interactive area remains at least 44×44 points

### Requirement: Recents explain their empty state
When no Activities exist, Recents SHALL present dedicated localized copy explaining that Activities the user tracks will appear there. The copy SHALL be the Recents section's own text, not the search sheet's empty-catalog copy.

#### Scenario: Empty catalog
- **WHEN** Track is idle and the catalog has no Activities
- **THEN** Recents shows the dedicated localized hint that tracked Activities will appear there

#### Scenario: First Activity created
- **WHEN** the user quick-creates the first Activity and returns to Track
- **THEN** the empty hint is replaced by Recents chips containing that Activity

### Requirement: Categories remain optional and separate from capture
The app SHALL treat Categories as optional, zero-or-more metadata on an Activity. Category management SHALL have its own surface, and an Activity created from capture SHALL be valid without notes or Categories. Activity search SHALL quick-create before any optional refinement and SHALL NOT display Category metadata in search results. Existing entries SHALL resolve the Activity's current Categories at query time.

#### Scenario: Create without categories
- **WHEN** the user quick-creates an unmatched Activity from search
- **THEN** the Activity is prepared and can start with no Categories assigned

#### Scenario: Assign categories to an existing Activity
- **WHEN** the user selects an existing Activity and opens the Activity Editor
- **THEN** the user may assign or remove zero or more Categories without making any Category required for timing

#### Scenario: Reclassify history
- **WHEN** the user changes an Activity's Categories
- **THEN** existing entries for that Activity use the updated Category set in Insights

### Requirement: First use is contextual
The app SHALL guide first-time users through their first Activity and timer through the ordinary native search-and-quick-create presentation, without a separate creation alert, configured-creation branch, blocking onboarding carousel, or account requirement.

#### Scenario: First local launch
- **WHEN** the user reaches Track with an empty catalog
- **THEN** the idle numeric timer and supporting copy direct the user to activate Activity search

#### Scenario: Search an empty catalog
- **WHEN** Activity search is active with an empty catalog and an empty query
- **THEN** the content area explains that no Activities exist and prompts the user to enter a name in the search field

#### Scenario: Enter the first valid name
- **WHEN** the empty-catalog user enters an unmatched valid name
- **THEN** one quick-create action becomes available and no configured-create action is presented

#### Scenario: First entry completed
- **WHEN** the user saves their first entry
- **THEN** the app confirms the result in context and does not interrupt the capture flow with unrelated sync, integration, or subscription prompts

### Requirement: Search drafts do not mutate committed preparation
Activity search SHALL maintain its query as a temporary draft separate from the committed prepared Activity until the user selects or creates an Activity.

#### Scenario: Search while an activity is ready
- **WHEN** the user activates the Activity picker while an Activity is prepared
- **THEN** search pre-fills and focuses the selected Activity name, retains that Activity as the committed selection, and does not replace it until another Activity is confirmed

#### Scenario: Edit the search query
- **WHEN** the user changes or clears the active search query
- **THEN** the prepared Activity and its identifier remain unchanged unless and until another Activity is confirmed

#### Scenario: Leave search without confirmation
- **WHEN** the search presentation ends without selecting or creating an Activity
- **THEN** the prior ready or idle timer state is restored exactly

### Requirement: Activity name collisions preserve one identity
Activity preparation and refinement SHALL treat names as equal after trimming surrounding whitespace and applying case-insensitive comparison. Creation and refinement SHALL recheck that identity at confirmation time so concurrent local or synchronized changes cannot create an intentionally duplicated Activity or silently merge two existing Activity identities.

#### Scenario: Case or surrounding whitespace differs
- **WHEN** the entered name differs from an existing Activity only by letter case or surrounding whitespace
- **THEN** the existing Activity is reused during creation and a duplicate is not created

#### Scenario: Collision occurs during quick creation
- **WHEN** another Activity with the same normalized name becomes available before quick creation commits
- **THEN** the app prepares the existing winning Activity instead of creating a duplicate

#### Scenario: Collision occurs during refinement
- **WHEN** refinement attempts to rename the selected Activity to another Activity's normalized name
- **THEN** the app keeps the original Activity selected, preserves the editor draft, presents a localized collision error, and does not overwrite or merge either Activity

#### Scenario: Matching Activity is pending deletion
- **WHEN** an Activity with the same normalized name remains restorable in the active deletion undo window
- **THEN** the app does not create a second identity and offers restoration of the pending-deletion Activity for preparation

### Requirement: Preparation failures preserve user intent
Activity search, creation, and selected-Activity refinement SHALL recover from local persistence failures without losing the user's search query or editor draft, replacing the committed prepared Activity, or changing timer state.

#### Scenario: Quick creation fails
- **WHEN** the local store cannot create an unmatched Activity
- **THEN** the search presentation remains active, the query is preserved, the previous committed timer state is unchanged, and a localized non-field error is presented

#### Scenario: Refinement fails
- **WHEN** the local store cannot save changes to the selected Activity
- **THEN** the editor remains available with its draft intact, the same Activity remains selected with its persisted values, the timer state is unchanged, and a localized error permits retry

#### Scenario: Prepared activity was deleted
- **WHEN** the committed prepared Activity no longer exists before Start is activated
- **THEN** the app clears the invalid preparation, returns to idle, and does not silently recreate the deleted Activity

### Requirement: Stop saves with stable feedback
Stopping a running timer SHALL save the completed entry locally, communicate success without a blocking loader, and retain the activity in the ready state for an optional later restart.

#### Scenario: Successful stop
- **WHEN** the user activates Stop on a running timer
- **THEN** the app persists the completed entry, clears running state, emits a success haptic, briefly confirms the saved duration, and returns to the ready numeric timer for the same Activity

#### Scenario: Save failure
- **WHEN** the local store cannot save the completed entry
- **THEN** the app preserves recoverable running state and presents a localized non-field error without silently losing elapsed time

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
