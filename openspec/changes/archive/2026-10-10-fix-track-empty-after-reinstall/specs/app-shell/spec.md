## MODIFIED Requirements

### Requirement: Three primary destinations
The app SHALL provide Track, History, and Insights as its primary destinations, and SHALL identify Track as the destination for starting and controlling a timer. The History destination SHALL present committed time entries as a day-grouped, read-only list (see `history-entry-list` capability). The Insights destination SHALL present a period-scoped breakdown of committed tracked time with a hero total (see `insights-breakdown` capability), replacing the empty-state placeholder whenever committed entries exist. The History destination SHALL show the navigation bar (inline title and Profile button) at rest and collapse it on scroll; the Profile button remains present on Track and Insights. The app SHALL require authentication before presenting any primary destination: when the user is signed out, the app SHALL render the auth flow full-screen in place of the shell and MUST NOT render Track, History, Insights, or the tab bar; primary destinations become reachable only after sign-in. While a cached session restore is in flight and its outcome is still unknown, the app SHALL render a restoring splash (activity indicator, app identity) instead of the auth flow, so a restorable session never flashes the login screen. The shell SHALL mount only after the signed-in account's local store is bound, buffered deletions are committed, and starter categories are seeded; the first-sync network pull stays background and MUST NOT block the reveal.

#### Scenario: Local launch
- **WHEN** the user launches the app signed out, with no account or active timer
- **THEN** the auth flow is presented full-screen instead of Track and the primary destinations are not reachable until sign-in succeeds

#### Scenario: Switching destinations
- **WHEN** the user selects History or Insights
- **THEN** the selected destination becomes visible without changing timer state or discarding the state of the previous destination

#### Scenario: Profile access on History
- **WHEN** the user is on History at rest (list at top) and wants to open Profile
- **THEN** the Profile button is visible in the navigation bar and opens Profile

#### Scenario: Insights shows breakdown
- **WHEN** the user selects Insights with committed entries on record
- **THEN** the period breakdown with hero total is shown instead of the empty-state placeholder

#### Scenario: Auth gate is not a sheet
- **WHEN** the user is signed out at launch
- **THEN** the auth flow covers the full screen with no shell visible behind it, and there is no way to dismiss it into the app without signing in

#### Scenario: Restoring session shows splash, not login
- **WHEN** the app launches with a cached session and tokens whose server validation is still in flight
- **THEN** the gate renders a restoring splash instead of the auth flow, and the auth flow appears only if the restore resolves to signed-out

#### Scenario: Shell mounts after local ready
- **WHEN** the user signs in (fresh, restored, or re-login) on a device whose account file needs binding, buffered-deletion commit, or starter seeding
- **THEN** the shell appears only after the bind, commit, and seed complete, so the first Track paint already carries starter categories and never flashes an empty store
