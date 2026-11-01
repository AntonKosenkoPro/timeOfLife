## MODIFIED Requirements

### Requirement: Search composes with History lifecycle and account isolation
The query SHALL survive same-account tab switches, entry/Profile navigation, local reloads, sync completion, and undo. Updated entries and category names SHALL be re-evaluated; results, highlights, excerpts, groups, and matching totals SHALL reflect the current snapshot. Search state and derived data SHALL reset on account change/sign-out and SHALL NOT be persisted across app launches or sent to logging/analytics. Row taps SHALL keep the existing form behavior. Log Time, nav-bar access, existing undo eligibility, and sync-only pull behavior SHALL remain intact; sync SHALL never be narrowed by the user query. No-match and invalid-query states SHALL offer no pull gesture.

#### Scenario: Editing removes a match
- **WHEN** the user edits a matching entry so it no longer satisfies the query and returns to History
- **THEN** the query remains and the entry disappears from results with groups and totals recomputed

#### Scenario: Reload and undo preserve the query
- **WHEN** sync changes entry/category data or an eligible deletion is undone
- **THEN** the current query is re-applied without being cleared and only currently matching entries appear

#### Scenario: Account isolation
- **WHEN** the user signs out or switches accounts after searching sensitive notes
- **THEN** no prior query, result, or excerpt is carried into the next account's History
