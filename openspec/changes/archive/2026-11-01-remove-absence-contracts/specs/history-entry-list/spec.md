## REMOVED Requirements

### Requirement: List content passes under the glass tab bar
**Reason**: One of its scenarios exists only to assert a removed timer stays gone; the requirement name is kept clean by replacing it.
**Migration**: Replacement requirement "Final row clears the tab bar" keeps the glass/opacity/inset behavior with a positively-worded reachability scenario.

### Requirement: History keeps a persistent nav bar
**Reason**: The "Compact timer on History" scenario exists only to assert a removed timer stays unrendered.
**Migration**: Replacement requirement "History nav bar stays visible" keeps the persistent nav-bar contract with positively-worded scenarios.

## ADDED Requirements

### Requirement: Final row clears the tab bar
On iOS 26 and later, the History list SHALL extend its scroll content beneath the bottom tab bar so rows blur behind the glass mid-scroll. On iOS 18 the tab bar SHALL render opaque so no scrolled content shows through it. On every OS the bottom content inset SHALL keep the final row fully reachable above the tab bar.

#### Scenario: Rows blur beneath the tab bar (iOS 26+)
- **WHEN** the user scrolls History so content crosses the tab-bar line on iOS 26 or later
- **THEN** rows pass visibly blurred beneath the bar with no hard cut at its top edge

#### Scenario: Default tab bar on iOS 18
- **WHEN** the user scrolls History on iOS 18
- **THEN** no scrolled content is visible through the bar (opaque bar)

#### Scenario: Final row reachable while timing
- **WHEN** the user scrolls to the final History row, whether or not a timer is running
- **THEN** the last entry row scrolls fully above the tab-bar chrome with no row permanently obscured

### Requirement: History nav bar stays visible
The History destination SHALL keep the navigation bar (inline "History" title and Profile button) permanently visible while History is on screen, regardless of list scroll position. The Profile button is reachable at all times on History.

#### Scenario: Nav bar visible while timing
- **WHEN** a timer is running and the user selects History
- **THEN** the inline "History" title and Profile button remain visible

#### Scenario: Navigation bar always visible
- **WHEN** the user scrolls the History list down and back up
- **THEN** the inline "History" title and Profile button remain visible at every scroll position

## MODIFIED Requirements

### Requirement: History shows committed time entries
The History destination SHALL display committed `TimeEntry` records as a chronological list, newest first, grouped by the day each entry started on. The list SHALL NOT show running (uncommitted) timer sessions. An empty or whitespace-only search query SHALL preserve the existing unfiltered History presentation. A valid non-empty query SHALL narrow the displayed entries according to `history-search`, retaining the same grouping and ordering and omitting days without matches. This narrowing applies to list updates from creation, editing, deletion, sync, and undo; a changed entry appears only if it matches the current query.

#### Scenario: History with entries
- **WHEN** the user selects History with a blank query and at least one committed time entry exists
- **THEN** the app shows a list of time entries grouped by day, newest day first, with entries within each day ordered newest first

#### Scenario: History with no entries
- **WHEN** the user selects History with a blank query and no committed time entries exist
- **THEN** the app shows the existing empty state (`historyEmptyTitle` / `historyEmptySubtitle`) and no list

#### Scenario: Running timer is not in History
- **WHEN** a timer is running and the user selects History
- **THEN** the running session does not appear as a History entry until the timer is stopped and saved

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
