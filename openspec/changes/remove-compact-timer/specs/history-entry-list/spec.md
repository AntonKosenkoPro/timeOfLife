## RENAMED Requirements

- FROM: `### Requirement: History preserves compact timer access with a persistent nav bar`
- TO: `### Requirement: History keeps a persistent nav bar`

## MODIFIED Requirements

### Requirement: History shows committed time entries
The History destination SHALL display committed `TimeEntry` records as a chronological list, newest first, grouped by the day each entry started on. The list SHALL NOT show running (uncommitted) timer sessions. Removing the compact timer SHALL NOT prevent newly saved timer entries from appearing when History is visible again or when an existing external-stop path saves while History remains visible.

#### Scenario: History with entries
- **WHEN** the user selects History and at least one committed time entry exists
- **THEN** the app shows a list of time entries grouped by day, newest day first, with entries within each day ordered newest first

#### Scenario: History with no entries
- **WHEN** the user selects History and no committed time entries exist
- **THEN** the app shows the existing empty state (`historyEmptyTitle` / `historyEmptySubtitle`) and no list

#### Scenario: Running timer is not in History
- **WHEN** a timer is running and the user selects History
- **THEN** the running session does not appear as a History entry until the timer is stopped and saved, and no in-app running-timer surface is shown

#### Scenario: Return after saving on Track
- **WHEN** the user stops and saves a timer on Track and returns to History
- **THEN** the saved entry appears in its day group and contributes to the day total without requiring a manual refresh

#### Scenario: Save through an existing external-stop path
- **WHEN** an existing external-stop path saves the running timer while History remains visible, or finishes while the app is backgrounded and History becomes visible again
- **THEN** History shows the committed entry and recomputed day total without requiring a tab switch or manual refresh after it becomes visible

#### Scenario: Off-screen event does not consume staleness
- **WHEN** History is off-screen and an external-stop or foreground event fires, and a notification-less save lands afterwards
- **THEN** the off-screen event marks History stale without reloading, and the next appear still reloads so the later save appears in its day group

#### Scenario: Search narrows existing day groups
- **WHEN** a valid non-empty query matches committed entries from some days
- **THEN** only those entries appear, once each, in their original start-day groups and newest-first ordering
- **AND** days with no matches have no header

### Requirement: List content passes under the glass tab bar
On iOS 26 and later, the History list SHALL extend its scroll content beneath the bottom tab bar so rows blur behind the glass mid-scroll. On iOS 18 the tab bar SHALL render opaque so no scrolled content shows through it. On every OS the bottom content inset SHALL keep the final row fully reachable above the tab bar without a compact-timer inset or placeholder.

#### Scenario: Rows blur beneath the tab bar (iOS 26+)
- **WHEN** the user scrolls History so content crosses the tab-bar line on iOS 26 or later
- **THEN** rows pass visibly blurred beneath the bar with no hard cut at its top edge

#### Scenario: Default tab bar on iOS 18
- **WHEN** the user scrolls History on iOS 18
- **THEN** no scrolled content is visible through the bar (opaque bar)

#### Scenario: Final row reachable with and without the compact timer
- **WHEN** the user scrolls to the final History row, whether or not a timer is running
- **THEN** no compact timer is shown in either state, and the last entry row scrolls fully above the tab-bar chrome with no row permanently obscured and no extra space reserved for a compact timer

### Requirement: History keeps a persistent nav bar
The History destination SHALL keep the navigation bar (inline "History" title and Profile button) permanently visible while History is on screen, regardless of list scroll position. The Profile button is reachable at all times on History.

#### Scenario: Compact timer on History
- **WHEN** a timer is running and the user selects History
- **THEN** no compact timer is rendered, the list uses only its ordinary tab-bar clearance, and the navigation bar remains visible

#### Scenario: Navigation bar always visible
- **WHEN** the user scrolls the History list down and back up
- **THEN** the inline "History" title and Profile button remain visible at every scroll position
