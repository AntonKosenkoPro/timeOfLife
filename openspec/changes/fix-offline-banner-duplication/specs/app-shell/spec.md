## MODIFIED Requirements

### Requirement: No global offline banner

The app SHALL NOT render a global offline banner on any tab. Offline state is surfaced only through the History pull-to-refresh offline notice (`HistoryPullModel` verdict → `PullNoticeBanner`) and the Profile sync-status row (`SyncController.status` error). The Track tab shows no offline hint.

#### Scenario: Offline on Track

- **WHEN** the user is signed in and offline on the Track tab
- **THEN** no banner or other global offline hint is shown and tracking keeps working fully offline

#### Scenario: Offline pull on History

- **WHEN** the user is signed in and offline and pulls to refresh the populated History list
- **THEN** the inline offline notice appears below the navigation bar (no sync cycle is burned) and auto-dismisses

#### Scenario: Offline status in Profile

- **WHEN** a sync cycle is skipped or fails for lack of connectivity
- **THEN** the Profile sync-status row shows the error state with its message until the next successful cycle
