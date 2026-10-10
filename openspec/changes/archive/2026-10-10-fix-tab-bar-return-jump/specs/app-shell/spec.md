## MODIFIED Requirements

### Requirement: Tab bar hidden on pushed destinations
The app SHALL hide the tab bar on every destination pushed past a tab root (Profile, Manage Categories, the pushed entry form, NamePicker), so a pushed page presents as a page with system Back and offers no tab-switch path while pushed. Returning via Back SHALL reveal the tab bar again on the originating tab root with its state intact, synchronously with the pop transition: the bar and the root content SHALL settle in a single coordinated layout pass with no post-settle relayout or content jump.

#### Scenario: Profile hides tabs
- **WHEN** the user opens Profile from any tab
- **THEN** the tab bar is hidden on Profile and no Track/History/Insights switch is reachable until Back

#### Scenario: Nested pushes keep tabs hidden
- **WHEN** the user navigates Profile → Manage Categories, History → entry form → NamePicker, or Track → NamePicker
- **THEN** the tab bar stays hidden at every depth and reappears only on return to the tab root

#### Scenario: No tab-switch-while-pushed
- **WHEN** a pushed destination is visible
- **THEN** there is no user-reachable path to change the selected tab without first navigating back

#### Scenario: Back reveals tab bar without relayout
- **WHEN** the user navigates back from any pushed destination to its originating tab root via the system Back button
- **THEN** the tab bar reappears as part of the pop transition and the root content holds its final layout with no second jump after the transition settles

#### Scenario: Cancelled swipe-back keeps tab bar hidden
- **WHEN** the user starts an interactive swipe-back from a pushed destination but releases without completing the pop
- **THEN** the pushed destination remains visible with the tab bar hidden and the originating tab root is unchanged

#### Scenario: Tab switch mid-push does not leak bar state
- **WHEN** a pushed destination is visible on one tab and the user returns to the tab bar path only via Back (no tab switch is reachable while pushed), then opens a destination on another tab
- **THEN** each tab's bar visibility follows only its own push depth: roots show the bar, pushed destinations hide it, independently per tab
