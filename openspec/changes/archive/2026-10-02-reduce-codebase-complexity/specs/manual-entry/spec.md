## MODIFIED Requirements

### Requirement: Log Time sheet captures name, start, end, categories, and notes
The app SHALL provide the Log Time sheet as the CREATE mode of the unified entry form (see entry-editor capability): cards in exactly this order — Name (plain-text entry-text field, never an activity picker), Start (date pill + time pill with inline single-open picker), End (date pill + time pill with inline single-open picker), Categories (ordered TagSelector), Notes (plain-text field, empty by default). An empty name SHALL mean no text is chosen and no entry text is pre-filled. CREATE mode SHALL keep the "Log time" title (localized) with an X dismiss action (`LogTimeDismissButton`) and a ✓ confirm action (`LogTimeAddButton`, localized VoiceOver labels, system-default toolbar tint) in the navigation bar, presented as a sheet from the existing entry points with unchanged defaults, gates, pickers, and save behavior. EDIT and LOCKED modes are defined by the entry-editor capability; no title, location, all-day, repeat, or alert fields SHALL be present in any mode. The all-native-gestures-must-work rule (entry-editor capability) SHALL apply to CREATE mode as well as EDIT/LOCKED.

#### Scenario: Sheet contents
- **WHEN** the Log Time sheet is open
- **THEN** it shows an X dismiss button and a ✓ confirm button (with the Log time title and the unchanged Name/Start/End/Categories/Notes cards) — and no Cancel/Add text buttons

#### Scenario: Cross discards the draft
- **WHEN** the user activates the X button
- **THEN** the sheet dismisses and no entry is created

#### Scenario: Create mode keeps its presentation
- **WHEN** the sheet opens from History for logging new time
- **THEN** it presents as a sheet (not a full-screen cover) with the "Log time" title and Cancel/Add actions
