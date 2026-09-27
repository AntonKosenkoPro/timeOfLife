## MODIFIED Requirements

### Requirement: Entry form shows a live duration subtitle in the navigation bar

The entry form SHALL show a live duration subtitle in the form's navigation bar in every mode (CREATE, EDIT, LOCKED): a `ToolbarItem(.principal)` VStack with the mode title (`Log Time` / `Edit entry` / `Imported entry`, localized) plus a footnote duration line. The duration line SHALL update live from the already-`@Published` `startsAt`/`endsAt`, formatted with the History natural-language duration (`33s`, `1m 20s`, `1h 12m`, `1d 12h`) prefixed by the localized `Duration` label. When the interval is invalid (End equal to or before Start, confirm disabled), the subtitle SHALL show a localized explanatory text (e.g. `End must be after Start`) in `Theme.danger` instead of a duration — it explains *why* the confirm action is disabled. The subtitle SHALL use `Theme` semantic colors only, with all user-facing strings localized (EN + RU); the footnote line SHALL be a single line (inline-mode truncation).

#### Scenario: Valid interval shows a live duration

- **WHEN** the form holds an end strictly after the start
- **THEN** the nav bar shows the mode title plus a footnote `Duration: <natural-language duration>` line that updates as Start/End change

#### Scenario: Invalid interval explains why the confirm is disabled

- **WHEN** the form holds an end equal to or before the start
- **THEN** the nav bar footnote shows the localized invalid-interval text in `Theme.danger` instead of a duration

#### Scenario: Locked mode keeps the read-only subtitle

- **WHEN** the form opens for an imported entry
- **THEN** the subtitle shows that entry's fixed interval duration (or the invalid text), never editable
