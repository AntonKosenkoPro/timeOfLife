## ADDED Requirements

### Requirement: Profile is a pushed page

The profile destination SHALL open as a pushed page on the current tab's navigation stack with the system back button, and SHALL NOT present as a sheet or offer a Done/dismiss control. Manage Categories SHALL keep pushing from Profile, and the category editor SHALL remain a sheet. Exiting Profile back to a tab SHALL restore the tab's prior state and reload Track data (recents + categories), so categories created in Profile are immediately usable.

#### Scenario: Open Profile from any tab
- **WHEN** the user taps the Profile button on Track, History, or Insights
- **THEN** Profile pushes onto that tab's navigation stack with a back button and no Done control

#### Scenario: Navigate back from Profile
- **WHEN** the user navigates back from Profile
- **THEN** the previously selected tab and its state are restored and Track data is reloaded

#### Scenario: Categories push unchanged
- **WHEN** the user opens Manage Categories from Profile
- **THEN** it pushes as before, and the category editor still opens as a sheet
