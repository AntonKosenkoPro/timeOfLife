# Category Management — refine-track-recents delta

## MODIFIED Requirements

### Requirement: Activities support optional multiple category assignments
The shared Activity editor SHALL display the available category catalog and allow zero, one, or multiple categories to be assigned to an Activity. Saving SHALL replace that Activity's category set as part of the same committed Activity edit. Category assignment SHALL remain optional. Track search results and the selected-Activity row SHALL NOT display Category metadata; Recents chips on Track SHALL display only the icon of the first Category assigned to an Activity (first by assignment position) and SHALL NOT display Category names.

#### Scenario: Assign multiple categories
- **WHEN** the user selects two or more categories in an Activity editor and saves
- **THEN** the Activity is associated with every selected category and the saved editor state reflects all selections

#### Scenario: Remove one assignment
- **WHEN** the user deselects one category while leaving others selected and saves
- **THEN** only the deselected association is removed

#### Scenario: Clear all assignments
- **WHEN** the user deselects every category and saves
- **THEN** the Activity remains valid with no categories and can still be prepared and timed

#### Scenario: Assignment save fails
- **WHEN** the Activity and its selected category set cannot be committed together
- **THEN** neither the Activity fields nor its persisted category set changes and the editor draft remains available for retry

#### Scenario: Capture remains category-free
- **WHEN** the user browses Track search results, the selected-Activity row, or Recents chips
- **THEN** no category is required for selecting or quick-creating an Activity, no Category name appears, and only Recents chips may display the icon of the first assigned Category

#### Scenario: Categoryless Activity chip has no icon
- **WHEN** a Recents chip's Activity has no assigned categories
- **THEN** the chip renders with the Activity name and no icon
