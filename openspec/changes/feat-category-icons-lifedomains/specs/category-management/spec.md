# Category Management — feat-category-icons-lifedomains delta

## MODIFIED Requirements

### Requirement: Every category has a valid name and icon
Each category SHALL have a name that is non-empty after trimming surrounding whitespace and no longer than 60 characters, and exactly one icon from the supported catalog SF Symbol set. The supported set is the pre-existing 47-symbol catalog PLUS the 16 life-domains symbols below (63 total; no renames, no removals — stored raw values keep syncing):

- Pets: `pawprint`, `dog`, `cat`, `fish`, `bird`
- Home + housekeeping: `washer`, `dryer`, `dishwasher`, `refrigerator`, `sofa`, `shower`, `lamp.table`
- People + family: `person.2`, `figure.and.child.holdinghands`
- Body + rest: `stethoscope`, `pill`

Category names SHALL be unique after trimming and case-insensitive comparison. Invalid input SHALL leave the persisted catalog unchanged and SHALL present one localized error for the affected field. Every catalog symbol SHALL have an EN + RU VoiceOver name (`L10n.catalogIconName`); the icon picker shows only symbols that render on the running OS (`CatalogIcon.renderableSymbols`), and a valid synchronized symbol that cannot render is displayed as `tag` without changing the stored value.

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
- **THEN** one category is created with the trimmed name and selected icon, and the icon renders in the category row, the picker, and (first-position) Recents chips / entry rows

#### Scenario: Dropped candidates are not selectable
- **WHEN** the user browses the icon picker on iOS 18
- **THEN** `turtle` and bare `lamp` are absent (both fail the runtime `canRender` check: `UIImage(systemName:)` returns nil), while `lamp.table` is present

#### Scenario: Existing icons are unchanged
- **WHEN** a category saved before this change syncs or renders after it
- **THEN** its stored icon raw value resolves to the same symbol as before (no renames or removals in the closed set)

#### Scenario: New icon has localized VoiceOver names
- **WHEN** VoiceOver focuses an icon option or category row using one of the 16 new symbols in English or Russian
- **THEN** it announces the localized icon meaning (e.g. "Paw print" / "След лапы") alongside the category name and action

#### Scenario: Icon is unsupported
- **WHEN** a category save carries an icon outside the supported catalog
- **THEN** the save is rejected and the persisted category remains unchanged
