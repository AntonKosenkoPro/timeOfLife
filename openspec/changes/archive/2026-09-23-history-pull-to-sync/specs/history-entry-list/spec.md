## ADDED Requirements

### Requirement: History pull-to-refresh triggers sync only

The populated History list SHALL offer a native pull-to-refresh gesture that runs a sync cycle only: it SHALL NOT perform an explicit local reload (the existing cycle-exit invalidate/reload remains the sole reload path). The empty state SHALL offer no pull gesture in this change. The native spinner SHALL tick exactly as long as the awaited cycle (fresh or joined) lasts.

#### Scenario: Pull with entries while signed in and online
- **WHEN** the user pulls on the populated History list while signed in and online with no cycle in flight
- **THEN** a sync cycle runs, the spinner ticks until it resolves, and the list reloads via the existing cycle-exit path

#### Scenario: Pull joins an in-flight cycle
- **WHEN** the user pulls while a cycle started by any other trigger is in flight
- **THEN** no second cycle starts; the spinner awaits the in-flight cycle's result

#### Scenario: Empty History has no pull
- **WHEN** History shows the empty state (no committed entries)
- **THEN** no pull-to-refresh gesture is offered

### Requirement: Signed-out pull shows a sign-in banner with link

A pull while signed out SHALL NOT start any sync network traffic. It SHALL present an inline notice below the navigation bar stating sign-in is required with a tappable sign-in link that opens the Enable Sync auth sheet (the existing auth flow, not a new entry point). The banner SHALL auto-dismiss after 5 seconds, reset its timer on re-pull, dismiss on navigation away, and dismiss early on successful sign-in (first-sync takes over).

#### Scenario: Signed-out pull
- **WHEN** the user pulls while signed out
- **THEN** no network traffic occurs and the signed-out banner with sign-in link appears

#### Scenario: Banner auto-dismiss
- **WHEN** the signed-out banner has been visible for 5 seconds without interaction
- **THEN** it dismisses on its own

#### Scenario: Sign-in link
- **WHEN** the user taps the sign-in link in the banner
- **THEN** the Enable Sync auth sheet opens; a successful sign-in dismisses the banner and starts first-sync

### Requirement: Offline pull shows an offline banner

A pull while signed in but offline SHALL NOT start a sync cycle. It SHALL present an inline notice in the same slot as the signed-out banner stating the device is offline (no action link), with the same 5-second auto-dismiss, re-pull reset, and dismiss-on-leave behavior. A connectivity loss mid-cycle (online at pull, offline during drain) SHALL surface as a cycle error dialog, not the offline banner.

#### Scenario: Offline pull
- **WHEN** the user pulls while signed in with no connectivity
- **THEN** no cycle starts and the offline banner appears in the banner slot

#### Scenario: Mid-cycle connectivity loss
- **WHEN** connectivity drops after a pull-started cycle began
- **THEN** the failure surfaces via the pull error dialog, not the offline banner

### Requirement: Pull-initiated sync failure shows an error dialog

A sync cycle awaited by a pull that ends in error SHALL present a modal dialog with a localized title, the captured secret-free error message as body, and a single OK button that dismisses it. Background cycle failures with no pull in flight SHALL NOT present the dialog (Profile status still reflects them).

#### Scenario: Failed pull shows dialog
- **WHEN** a pull-awaited cycle (fresh or joined) fails
- **THEN** the error dialog appears with the captured message and an OK button

#### Scenario: Background failure shows no dialog
- **WHEN** a foreground/connectivity cycle fails while History is visible with no pull in flight
- **THEN** no dialog appears over History
