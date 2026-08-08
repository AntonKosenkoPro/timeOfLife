## MODIFIED Requirements

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
Track SHALL provide one platform-native search presentation for browsing, filtering, selecting, and creating Activities without requiring network access. The presentation SHALL be a searchable sheet opened by exactly one state-specific preparation control: the idle `+ Choose an activity` primary button or the ready Activity picker. The operating system SHALL own search-field placement, focus, keyboard, activation animation, and cancellation affordances inside the sheet. The search content SHALL NOT display Category metadata on existing Activity results.

#### Scenario: Activate Activity search from idle
- **WHEN** no Activity is prepared and the user activates `+ Choose an activity`
- **THEN** the searchable sheet presents Activity-selection content with an empty, focused native search field without changing the committed timer state

#### Scenario: Activate Activity search from ready
- **WHEN** an Activity is prepared and the user activates the Activity picker
- **THEN** the searchable sheet presents Activity-selection content with the selected Activity name pre-filled and the native search field focused without changing the committed timer state

#### Scenario: Show one preparation control
- **WHEN** Track is idle or ready
- **THEN** it presents only the state-specific preparation control below the numeric timer and above Recents

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
- **THEN** the content area offers both quick creation of that exact name and optional configured creation with the name prefilled

#### Scenario: Quick-create an unmatched activity
- **WHEN** the user confirms quick creation for an unmatched valid name
- **THEN** the app creates the Activity locally without Categories, dismisses the search presentation, and prepares it

#### Scenario: Invalid creation input
- **WHEN** the trimmed query is empty or violates Activity-name validation
- **THEN** no create action is enabled and a localized validation explanation is available without preventing search of existing Activities

#### Scenario: Dismiss the search presentation
- **WHEN** the user activates the native search cancellation affordance or dismisses the sheet without confirming
- **THEN** the search presentation ends and Track restores the Activity that was prepared before search, or idle state if none was prepared

### Requirement: Categories remain optional and separate from capture
The app SHALL treat Categories as optional, zero-or-more metadata on an Activity. Category management SHALL have its own surface, and an Activity created from capture SHALL be valid without Categories. Configured creation from Activity search SHALL use the shared Activity Editor without displaying Category metadata in search results. Existing entries SHALL resolve the Activity's current Categories at query time.

#### Scenario: Create without categories
- **WHEN** the user quick-creates an unmatched Activity from search
- **THEN** the Activity is prepared and can start with no Categories assigned

#### Scenario: Configure before creation
- **WHEN** the user activates configuration for an unmatched valid query
- **THEN** the shared Activity Editor opens with the trimmed name prefilled and permits optional notes and Categories

#### Scenario: Save configured activity
- **WHEN** the user successfully saves configured creation
- **THEN** the editor and search presentation close and the saved Activity is prepared without starting timing

#### Scenario: Cancel configured activity
- **WHEN** the user cancels configured creation before saving
- **THEN** no Activity is created and the app returns to the active search presentation with the prior query preserved

#### Scenario: Assign categories later
- **WHEN** the user opens the full Activity Editor for an existing Activity
- **THEN** the user may assign or remove zero or more Categories without making any Category required for timing

#### Scenario: Reclassify history
- **WHEN** the user changes an Activity's Categories
- **THEN** existing entries for that Activity use the updated Category set in Insights

### Requirement: First use is contextual
The app SHALL guide first-time users through their first Activity and timer through the ordinary native search-and-create presentation, without a separate creation alert, blocking onboarding carousel, or account requirement.

#### Scenario: First local launch
- **WHEN** the user reaches Track with an empty catalog
- **THEN** the idle numeric timer and supporting copy direct the user to activate Activity search

#### Scenario: Search an empty catalog
- **WHEN** Activity search is active with an empty catalog and an empty query
- **THEN** the content area explains that no Activities exist and prompts the user to enter a name in the search field

#### Scenario: Enter the first valid name
- **WHEN** the empty-catalog user enters an unmatched valid name
- **THEN** the same quick-create and configured-create actions used for every unmatched name become available

#### Scenario: First entry completed
- **WHEN** the user saves their first entry
- **THEN** the app confirms the result in context and does not interrupt the capture flow with unrelated sync, integration, or subscription prompts

## ADDED Requirements

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
Activity preparation SHALL treat names as equal after trimming surrounding whitespace and applying case-insensitive comparison. Creation SHALL recheck that identity at confirmation time so concurrent local or synchronized changes cannot create an intentionally duplicated Activity through this flow.

#### Scenario: Case or surrounding whitespace differs
- **WHEN** the entered name differs from an existing Activity only by letter case or surrounding whitespace
- **THEN** the existing Activity is reused and a duplicate is not created

#### Scenario: Collision occurs during quick creation
- **WHEN** another Activity with the same normalized name becomes available before quick creation commits
- **THEN** the app prepares the existing winning Activity instead of creating a duplicate

#### Scenario: Collision occurs during configured creation
- **WHEN** configured creation is saved after another Activity with the same normalized name has become available
- **THEN** the app does not overwrite the existing Activity's notes or Categories and offers the user a choice to use the existing Activity or continue editing a distinct name

#### Scenario: Matching Activity is pending deletion
- **WHEN** an Activity with the same normalized name remains restorable in the active deletion undo window
- **THEN** the app does not create a second identity and offers restoration of the pending-deletion Activity for preparation

### Requirement: Preparation failures preserve user intent
Activity search and creation SHALL recover from local persistence failures without losing the user's query or replacing the committed prepared Activity.

#### Scenario: Quick creation fails
- **WHEN** the local store cannot create an unmatched Activity
- **THEN** the search presentation remains active, the query is preserved, the previous committed timer state is unchanged, and a localized non-field error is presented

#### Scenario: Configured creation fails
- **WHEN** the local store cannot save configured creation
- **THEN** the editor remains available with its draft intact and presents a localized error that permits retry

#### Scenario: Prepared activity was deleted
- **WHEN** the committed prepared Activity no longer exists before Start is activated
- **THEN** the app clears the invalid preparation, returns to idle, and does not silently recreate the deleted Activity
