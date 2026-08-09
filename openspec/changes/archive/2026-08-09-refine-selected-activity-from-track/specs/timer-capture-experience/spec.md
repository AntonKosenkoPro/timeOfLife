## ADDED Requirements

### Requirement: Selected Activities can be refined from Track
Track SHALL expose a distinct Refine action beside the selected Activity whenever an Activity is selected. Activating Refine SHALL open the shared Activity Editor for that Activity with its current name, notes, and Categories prefilled. Refinement SHALL preserve the Activity identifier and SHALL NOT start, stop, reset, or replace the timer state.

#### Scenario: No Activity selected
- **WHEN** Track has no selected Activity
- **THEN** no Refine action is presented

#### Scenario: Activity selected
- **WHEN** Track displays a selected Activity in ready, running, saving, saved, or recoverable error state
- **THEN** a distinct Refine action is presented immediately beside the selected Activity

#### Scenario: Refine a newly created Activity
- **WHEN** the user quick-creates an Activity and activates Refine beside the resulting Track selection
- **THEN** the Activity Editor opens in edit mode with that Activity's current values prefilled

#### Scenario: Refine an existing Activity
- **WHEN** the user selects an existing Activity and activates Refine
- **THEN** the Activity Editor opens in edit mode with its persisted name, notes, and Categories prefilled

#### Scenario: Save refinement
- **WHEN** the user saves valid changes in the Activity Editor
- **THEN** the editor closes, the same Activity identifier remains selected, the Track row reflects the saved values, and the timer state is unchanged

#### Scenario: Cancel refinement
- **WHEN** the user dismisses or cancels refinement without saving
- **THEN** the editor closes, the Activity remains unchanged and selected, and the timer state is unchanged

#### Scenario: Refinement fails
- **WHEN** refinement cannot be saved
- **THEN** the editor remains available with the draft intact, a localized error permits retry, and the selected Activity and timer state remain unchanged

## MODIFIED Requirements

### Requirement: Activity chooser supports selection and creation
Track SHALL provide one platform-native search presentation for browsing, filtering, selecting, and quick-creating Activities without requiring network access. The presentation SHALL be a searchable sheet opened by the idle `+ Choose an activity` primary button or by the Activity picker within the selected-Activity row. When an Activity is selected, the row SHALL place a distinct Refine action immediately beside the Activity picker. The operating system SHALL own search-field placement, focus, keyboard, activation animation, and cancellation affordances inside the sheet. The search content SHALL NOT display Category metadata on existing Activity results and SHALL NOT offer configured creation or open the Activity Editor before creation.

#### Scenario: Activate Activity search from idle
- **WHEN** no Activity is prepared and the user activates `+ Choose an activity`
- **THEN** the searchable sheet presents Activity-selection content with an empty, focused native search field without changing the committed timer state

#### Scenario: Activate Activity search from ready
- **WHEN** an Activity is prepared and the user activates the Activity picker
- **THEN** the searchable sheet presents Activity-selection content with the selected Activity name pre-filled and the native search field focused without changing the committed timer state

#### Scenario: Show state-specific preparation actions
- **WHEN** Track is idle
- **THEN** it presents one `+ Choose an activity` preparation control below the numeric timer and above Recents, with no Refine action

#### Scenario: Show selected-Activity actions
- **WHEN** Track has a selected Activity
- **THEN** it presents the Activity picker or non-interactive Activity label and the distinct Refine action together in one row below the numeric timer and above Recents

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
- **THEN** the app creates the Activity locally without notes or Categories, dismisses the search presentation, prepares it, and exposes Refine beside it on Track

#### Scenario: Invalid creation input
- **WHEN** the trimmed query is empty or violates Activity-name validation
- **THEN** no create action is enabled and a localized validation explanation is available without preventing search of existing Activities

#### Scenario: Dismiss the search presentation
- **WHEN** the user activates the native search cancellation affordance or dismisses the sheet without confirming
- **THEN** the search presentation ends and Track restores the Activity that was prepared before search, or idle state if none was prepared

### Requirement: Categories remain optional and separate from capture
The app SHALL treat Categories as optional, zero-or-more metadata on an Activity. Category management SHALL have its own surface, and an Activity created from capture SHALL be valid without notes or Categories. Activity search SHALL quick-create before any optional refinement and SHALL NOT display Category metadata in search results. The selected Activity MAY be refined afterward through the shared Activity Editor. Existing entries SHALL resolve the Activity's current Categories at query time.

#### Scenario: Create without categories
- **WHEN** the user quick-creates an unmatched Activity from search
- **THEN** the Activity is prepared and can start with no Categories assigned

#### Scenario: Refine after creation
- **WHEN** the user wants to add notes or Categories to an Activity created from search
- **THEN** the user first creates and prepares the Activity, then activates Refine beside it on Track

#### Scenario: Assign categories to an existing Activity
- **WHEN** the user selects an existing Activity and opens Refine
- **THEN** the user may assign or remove zero or more Categories without making any Category required for timing

#### Scenario: Reclassify history
- **WHEN** the user changes an Activity's Categories
- **THEN** existing entries for that Activity use the updated Category set in Insights

### Requirement: First use is contextual
The app SHALL guide first-time users through their first Activity and timer through the ordinary native search-and-quick-create presentation, without a separate creation alert, configured-creation branch, blocking onboarding carousel, or account requirement. Optional refinement SHALL become available on Track after the first Activity is created and selected.

#### Scenario: First local launch
- **WHEN** the user reaches Track with an empty catalog
- **THEN** the idle numeric timer and supporting copy direct the user to activate Activity search

#### Scenario: Search an empty catalog
- **WHEN** Activity search is active with an empty catalog and an empty query
- **THEN** the content area explains that no Activities exist and prompts the user to enter a name in the search field

#### Scenario: Enter the first valid name
- **WHEN** the empty-catalog user enters an unmatched valid name
- **THEN** one quick-create action becomes available and no configured-create action is presented

#### Scenario: Refine the first Activity
- **WHEN** the user quick-creates their first Activity
- **THEN** search closes, the Activity is prepared, and Refine becomes available beside it on Track

#### Scenario: First entry completed
- **WHEN** the user saves their first entry
- **THEN** the app confirms the result in context and does not interrupt the capture flow with unrelated sync, integration, or subscription prompts

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
