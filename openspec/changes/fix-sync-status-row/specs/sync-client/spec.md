## MODIFIED Requirements

### Requirement: Manual sync and status visibility
The system SHALL expose a "Sync now" action and a sync status ("Synced successfully" with a relative-age subtitle, "Syncing…", or an error state) in Profile, visible only when signed in. The action calls the same drain+pull path as the automatic triggers. While a sync is in progress, the "Sync now" button SHALL keep its title (disabled) and the status row SHALL be the single "Syncing…" surface — never two. A failed cycle SHALL surface its captured error message alongside the generic error state (secret-free: codes and server messages only). Status views SHALL subscribe to the sync status directly rather than through a non-publishing intermediary, so the display follows the cycle on its own. The idle status SHALL render a "Synced successfully" title with an age subtitle. The subtitle SHALL be minute-bucketed with no seconds precision: under a minute, whole minutes 1–59, whole hours 1–23, whole days 24 hours and up with no upper cap (never weeks, months, or years); a timestamp in the future SHALL render as under a minute. The row SHALL re-render its subtitle on its own as time passes while Profile is visible, with no user action. The subtitle SHALL be correctly localized in English + Russian with correct plural forms: quantity words MAY be rendered by the system quantity formatter (which owns pluralization in every locale), and all connective words SHALL come from localizable strings — no system relative-time formatter with automatic unit choice and tense.

#### Scenario: Status display
- **WHEN** the user views Profile while signed in
- **THEN** the sync status and "Sync now" button are visible; while a sync is in progress, the button is disabled under its own title and exactly one "Syncing…" indicator is shown

#### Scenario: Status follows the cycle without manual refresh
- **WHEN** a sync cycle completes (or fails) while Profile is visible
- **THEN** the status row and button state update on their own — no navigation or re-render trigger needed

#### Scenario: Status row keeps its height across states
- **WHEN** the user taps "Sync now" with a previous successful sync on record
- **THEN** the row stays two lines through syncing (previous age as the subtitle) into the new idle age — the section below never jumps

#### Scenario: Error state
- **WHEN** a sync cycle fails (network error, 5xx)
- **THEN** the status shows an error with its captured message and the "Sync now" button remains enabled to allow retry

#### Scenario: Minute buckets
- **WHEN** the last sync was 30 seconds, 1 minute, 59 minutes, 1 hour, 23 hours, 1 day, or 400 days ago
- **THEN** the subtitle reads under-a-minute, "1 minute ago", "59 minutes ago", "1 hour ago", "23 hours ago", "1 day ago", or "400 days ago" respectively beneath a "Synced successfully" title — seconds and weeks/months/years never appear

#### Scenario: Label ages live
- **WHEN** the user keeps Profile open across a minute boundary with no new sync
- **THEN** the subtitle advances to the next bucket on its own

#### Scenario: Future timestamp never reads as future
- **WHEN** the recorded sync date is ahead of the device clock (clock skew)
- **THEN** the subtitle reads under-a-minute — never a future-tense phrase in any locale

#### Scenario: Label is fully localized
- **WHEN** the app runs in Russian
- **THEN** every subtitle (including 1/2/5-form plurals) reads correctly in Russian with no system-generated tense or unit choice

#### Scenario: Future language cost stays flat
- **WHEN** a new locale is added later
- **THEN** only connective words need new strings — quantity pluralization already works through the system quantity formatter
