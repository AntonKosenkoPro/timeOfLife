## MODIFIED Requirements

### Requirement: A starter category set is created once
The system SHALL create exactly one starter set for a new local dataset containing Work (`briefcase`), Hobby (`paintbrush`), Sport (`figure.run`), Education (`book`), Relax (`cup.and.saucer`), Sleep (`bed.double`), Entertainment (`tv`), and Food (`fork.knife`). Starter names SHALL use the app's active supported language when the records are first created, covering `en`, `ru`, `zh-Hans`, `es-419`, and `pt-BR`. Starter categories SHALL thereafter behave as ordinary user records and SHALL NOT be recreated merely because the user edits or deletes them. Already-seeded datasets SHALL NOT receive Food through an upgrade/backfill or initialization retry, or have their existing categories renamed, re-iconed, or recreated by this update. Ordinary user creation and synchronization of categories SHALL remain unchanged.

#### Scenario: First launch in English
- **WHEN** a new local dataset is initialized while English is active
- **THEN** the eight starter categories, including Food with `fork.knife`, are available with their English names and specified icons before category management or entry editing is shown

#### Scenario: First launch in Russian
- **WHEN** a new local dataset is initialized while Russian is active
- **THEN** the same eight starter categories are available with localized Russian names and the same specified icons

#### Scenario: First launch in another supported language
- **WHEN** a new local dataset is initialized in Simplified Chinese, Latin American Spanish, or Brazilian Portuguese
- **THEN** the same eight starter categories, including Food, use the active language's names and the same specified icons

#### Scenario: Initialization is retried
- **WHEN** starter initialization is attempted again after the starter set was committed
- **THEN** no starter category is duplicated or recreated

#### Scenario: An existing seven-starter dataset is reopened
- **WHEN** a dataset seeded before Food was introduced is opened after the update without incoming category changes
- **THEN** starter initialization adds no Food category and all surviving category names and icons remain unchanged

#### Scenario: User deletes every starter category
- **WHEN** the user deletes all starter categories and their buffered deletions are committed
- **THEN** the category catalog remains empty until the user creates or synchronizes a category

#### Scenario: App language changes after seeding
- **WHEN** the app language changes after starter categories were created
- **THEN** existing category records retain their current user-editable names and are not silently renamed

#### Scenario: Local data is explicitly erased
- **WHEN** the user erases the active local dataset and a new dataset is initialized
- **THEN** the new dataset receives the eight-starter set once without changing dormant account datasets

### Requirement: Every category has a valid name and icon
Each category SHALL have a name that is non-empty after trimming surrounding whitespace and no longer than 60 characters, and exactly one icon from the supported catalog SF Symbol set. The supported set SHALL retain all existing 63 symbols, including the 16 life-domains symbols below, without renaming or removing any existing raw value:

- Pets: `pawprint`, `dog`, `cat`, `fish`, `bird`
- Home + housekeeping: `washer`, `dryer`, `dishwasher`, `refrigerator`, `sofa`, `shower`, `lamp.table`
- People + family: `person.2`, `figure.and.child.holdinghands`
- Body + rest: `stethoscope`, `pill`

The supported catalog SHALL add exactly three symbols: `carrot`, `stroller`, and `teddybear`, for exactly 66 accepted symbols. New-selection food choices SHALL be `fork.knife`, `cup.and.saucer`, and `carrot`; child-specific choices SHALL be `figure.and.child.holdinghands`, `stroller`, and `teddybear`. Each requested domain SHALL therefore contain exactly three choices including existing symbols. Generic `person.2` SHALL remain unchanged and SHALL NOT count toward the child-specific total. All three additions SHALL render on iOS 18. If verification of any addition fails, this expansion SHALL NOT ship until an explicit decision revises the agreed set; no icon SHALL be silently omitted or substituted.

Category names SHALL be unique after trimming and case-insensitive comparison. Invalid input SHALL leave the persisted catalog unchanged and SHALL present one localized error for the affected field. Every supported symbol SHALL have a localized VoiceOver name in all five supported languages.

The new-selection picker SHALL show only supported symbols that render on the running OS, excluding exactly eight sports symbols: `figure.strengthtraining`, `figure.soccer`, `figure.basketball`, `figure.tennis`, `figure.gymnastics`, `figure.mindandbody`, `figure.core.training`, and `bicycle`. The six retained sports choices SHALL remain offered where renderable: `figure.walk`, `figure.run`, `dumbbell`, `figure.yoga`, `figure.cycling`, and `figure.swimming`. Hiding SHALL NOT affect validation, storage, synchronization, or display outside new selection. When editing a category, its currently selected supported icon SHALL remain represented even if hidden from new selection or unavailable on the OS. A supported icon that cannot render SHALL display as `tag` without changing the stored value; hiding alone SHALL NOT cause this fallback.

#### Scenario: Create a valid category
- **WHEN** the user enters a unique valid name, selects a supported icon, and saves
- **THEN** one category is created with the trimmed name and selected icon

#### Scenario: Name is empty
- **WHEN** the user attempts to save a category whose name contains only whitespace
- **THEN** no category is created or updated and a localized name-required error is shown beneath the name field

#### Scenario: Name exceeds the limit
- **WHEN** the user attempts to save a category whose name exceeds 60 characters
- **THEN** no category is created or updated and a localized name-length error is shown beneath the name field

#### Scenario: Name collides by case or whitespace
- **WHEN** the user attempts to create or rename a category to a name that differs from another category only by case or surrounding whitespace
- **THEN** neither category is overwritten or merged and a localized duplicate-name error permits correction

#### Scenario: Create a category with a life-domains icon
- **WHEN** the user enters a unique valid name, selects one of the 16 life-domains icons (e.g. `pawprint`, `washer`, `person.2`, `stethoscope`), and saves
- **THEN** one category is created with the trimmed name and selected icon, and the icon renders in the category row, the picker, and first-position Recents chips and entry rows

#### Scenario: Dropped candidates are not selectable
- **WHEN** the user browses new icon choices on iOS 18
- **THEN** the previously excluded `turtle` and bare `lamp` remain absent, while `lamp.table` remains present

#### Scenario: Existing icons are unchanged
- **WHEN** a category saved before this change syncs or renders after it
- **THEN** its stored icon raw value resolves to the same symbol as before, including hidden sports symbols

#### Scenario: New icon has localized VoiceOver names
- **WHEN** VoiceOver focuses an icon option or category row in any supported language
- **THEN** it announces the localized icon meaning alongside the applicable category name and action, rather than a raw symbol identifier

#### Scenario: Icon is unsupported
- **WHEN** a category save carries an icon outside the supported catalog
- **THEN** the save is rejected and the persisted category remains unchanged

#### Scenario: New sports choices are compact
- **WHEN** a user creates a category and browses sports icon choices
- **THEN** the eight hidden sports symbols, including `bicycle`, are absent and the six retained choices, including `figure.cycling`, are offered where renderable

#### Scenario: A hidden selected icon survives editing
- **WHEN** the user opens a category with `figure.soccer` or `bicycle`, changes only its name, and saves
- **THEN** the current icon is represented in the editor and its stored raw value is preserved locally and by the relay
- **AND** it displays its original glyph wherever renderable, not `tag` merely because it is hidden

#### Scenario: A hidden selected icon is explicitly replaced
- **WHEN** the user chooses a different visible icon while editing a category with a hidden sports icon and saves
- **THEN** only that explicit selection changes the stored icon

#### Scenario: A supported selected icon cannot render on this OS
- **WHEN** the user edits or views a synchronized category with a supported but unavailable symbol
- **THEN** it is represented with `tag` while preserving its stored raw value unless the user explicitly selects another icon

#### Scenario: The three new icons are available on iOS 18
- **WHEN** the user browses food/drink and child-specific choices on iOS 18
- **THEN** `carrot`, `stroller`, and `teddybear` are available and each domain contains its three specified choices

#### Scenario: New symbols sync successfully
- **WHEN** a category uses `carrot`, `stroller`, or `teddybear` and is saved offline then synchronized
- **THEN** both client and relay accept the identical raw value and synchronization preserves it
