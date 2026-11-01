# History Search Specification

## Purpose

Lets users find committed entries locally through a compact History search field with scoped text terms and precise start-date constraints, while retaining familiar day groups and explaining text matches.

## Requirements

### Requirement: History offers an inline local search field
History SHALL offer one always-visible search field pinned with its list, using the native navigation-bar drawer that hides on scroll and returns on scroll-up. There SHALL be no activation button, modes, or separate filter panel: the field is simply there, and a blank query shows normal History. Search SHALL refine the active account's locally available committed entries as the query changes, without requiring submission, connectivity, or a server request. It SHALL NOT offer autocomplete, qualifier or value suggestions, recent searches, automatic date insertion, token chips, or a scope bar. The field SHALL remain usable when the query has no matches or invalid syntax. Search SHALL NOT mutate stored entries or include running drafts.

#### Scenario: Offline search
- **WHEN** a signed-in user enters a valid query while offline
- **THEN** History searches that account's local committed entries without making a network request

#### Scenario: Manual entry of syntax
- **WHEN** the user types `in:` or `started:`
- **THEN** no completion, suggestion list, or date picker appears

#### Scenario: Field placement follows the list
- **WHEN** the user opens History and scrolls the list
- **THEN** the search field stays pinned with the list content, hiding on scroll-down and returning on scroll-up, with no activation step and no layout jump

#### Scenario: Tab bar hides only while filtering
- **WHEN** the query is blank (normal History, field merely visible)
- **THEN** the bottom tab bar stays visible, so focusing the empty field causes no chrome change
- **AND WHEN** the query becomes non-blank (results, no-matches, or syntax-diagnostic states)
- **THEN** the bottom tab bar hides with an animated transition, giving results the full content height
- **AND** clearing the query back to blank restores the tab bar the same way

### Requirement: Blank queries restore normal History
An empty or whitespace-only query SHALL show exactly the existing unfiltered History content and behavior: chronological day groups, full-day totals labeled “tracked”, unchanged row presentation and notes indicators, and the existing empty-History state when there are no committed entries. Blank queries SHALL NOT produce text highlights or notes excerpts. This invariant concerns the list and its behavior, not removal of the newly available search field.

#### Scenario: Clearing a query
- **WHEN** the user clears a query after viewing highlighted results with notes excerpts
- **THEN** all locally available committed entries return in their normal groups with full-day “tracked” totals and no highlights or notes excerpts

#### Scenario: Whitespace-only query
- **WHEN** the query contains only spaces or line-break whitespace
- **THEN** the list behaves identically to an empty query

### Requirement: Plain text defaults to name-and-category search
Plain text SHALL search entry names and category names (a union: each term may match either field). `gym` and `gym in:name,categories` SHALL yield the same entries. Matching SHALL use case-insensitive Unicode-aware substring comparison while preserving the original entry text and its exact case-sensitive identity. Accent differences SHALL remain significant in this version. Whitespace SHALL separate unquoted terms; every term SHALL match at least one selected field on the same entry. Double quotes SHALL delimit a single phrase, preserving its internal whitespace. Quoted `\"` and `\\` SHALL represent a literal quote and backslash. Apostrophes SHALL be ordinary text, not phrase delimiters. The uppercase words `AND` and `OR` SHALL be boolean operators, never text terms; lowercase `and`/`or` SHALL be ordinary text.

#### Scenario: Default scope searches names and categories
- **WHEN** `Gym` appears in an entry's name or in one of its category names and the user searches `gym`
- **THEN** that entry matches, while an entry with `Gym` only in its notes does not

#### Scenario: Substring matching preserves identity
- **WHEN** the user searches `gym` and entries are named `Morning Gym` and `GYM`
- **THEN** both entries match and retain their distinct names and identities

#### Scenario: Terms and phrases
- **WHEN** the user searches `morning gym`
- **THEN** both terms must appear in the selected fields, regardless of their order
- **AND** searching `"morning gym"` instead requires that contiguous phrase

### Requirement: Explicit AND and OR combine match groups
A query SHALL be an alternation of one or more groups separated by the `OR` operator; each group SHALL be a conjunction of items separated by whitespace or the `AND` operator. `AND` SHALL bind tighter than `OR`; operators of equal precedence SHALL associate left. Parentheses SHALL NOT be supported and SHALL produce a syntax diagnostic. Only fully uppercase `AND`/`OR` SHALL be operators: any other casing, and quoted `"AND"`/`"OR"`, SHALL be ordinary text terms. A leading, trailing, or doubled operator SHALL produce a syntax diagnostic. `in:` qualifiers SHALL remain global to the whole query (a union over all groups); `started:`, `ended:`, and `has:` qualifiers SHALL bind to the group in which they appear. Queries without `OR` SHALL behave exactly as before (a single group).

#### Scenario: Alternation across groups
- **WHEN** the user searches `gym OR run`
- **THEN** entries matching either term (in the selected fields) appear once each

#### Scenario: Precedence without parentheses
- **WHEN** the user searches `gym run OR swim started:>=2026-10-01`
- **THEN** it means `(gym AND run) OR (swim AND started:>=2026-10-01)`

#### Scenario: Lowercase operators are text
- **WHEN** a note contains the text `fish and chips` and the user searches `fish and chips in:notes`
- **THEN** all three words are required text terms

#### Scenario: Qualifier binding follows groups
- **WHEN** the user searches `gym started:>=2026-10-01 OR run`
- **THEN** the date constraint applies only to the `gym` group, and any `run` entry from any date matches

### Requirement: The in qualifier selects global text fields
`in:` SHALL accept `name`, `categories`, and `notes`. The complete qualifier SHALL be one unquoted token with no whitespace between `in:`, its field names, and scope-list commas; quoted qualifier values SHALL NOT be accepted. The default scope SHALL be `name,categories`; any explicit `in:` SHALL replace that default. Comma-separated fields and repeated `in:` qualifiers SHALL form a union, independent of their position in the query. Each text term SHALL match at least one field in that union; separate terms within a group SHALL combine with AND. Category matching SHALL inspect every attached category's current visible name, not only the first category, and SHALL use the same substring rule as other text fields. Notes SHALL search their plain-text contents. Source labels, dates, durations, icons, and day headings SHALL NOT be text-search fields. A scope with no text terms SHALL add no field-content or field-presence constraint.

#### Scenario: Search categories
- **WHEN** the user searches `sport in:categories`
- **THEN** entries whose attached category names contain `sport` match, even when the matching category is not first

#### Scenario: Search several fields
- **WHEN** the user searches `gym stretch in:name,notes`
- **THEN** an entry named `Gym` with notes containing `stretching` matches
- **AND** it appears only once

#### Scenario: Scope is global and replaces the default
- **WHEN** the user searches `gym in:notes` or `in:notes gym`
- **THEN** both queries search notes only and return the same entries

#### Scenario: Repeated and scope-only qualifiers
- **WHEN** the user searches `gym in:name in:notes`
- **THEN** it is equivalent to `gym in:name,notes`
- **AND** `in:notes` without text or a start constraint returns all committed entries rather than implying “has notes”

### Requirement: Start constraints support comparisons and ranges
`started:` SHALL constrain an entry's start, not its end or overlap with an interval. It SHALL accept a bare operand, the comparisons `>`, `>=`, `<`, `<=`, an inclusive range `A..B`, and open ranges `A..*` or `*..B`. The complete qualifier SHALL be one unquoted token, with no whitespace after its colon, between a comparison and operand, or around a range separator. Quoted qualifier values SHALL NOT be accepted. A standalone unquoted `..` SHALL be a syntax error rather than a text term; the complete phrase can be quoted when literal operator text is intended. Operands SHALL be calendar dates, explicit-offset timestamps, or times of day (see the time-of-day requirement). Date and timestamp endpoints MAY mix in one range (each normalized by its own rule); clock-time endpoints SHALL pair only with clock-time endpoints, and any other mixed-kind range SHALL be a syntax diagnostic. Multiple start constraints within a group SHALL combine with AND, and the combined start constraint SHALL combine with the group's text matching using AND. Queries containing only start constraints SHALL be valid. A bare timestamp SHALL mean exact instant equality, without rounding the stored start time. Negated time qualifiers (e.g. `-started:`) SHALL NOT be supported and SHALL produce a syntax diagnostic.

#### Scenario: Text and date constraints combine
- **WHEN** the user searches `gym in:name,notes started:>=2026-10-01`
- **THEN** an entry must satisfy both the scoped text query and the start constraint

#### Scenario: Start, not interval overlap
- **WHEN** an entry starts before a queried local day but ends during it
- **THEN** `started:` for that day does not match the entry

#### Scenario: Open and conjunctive bounds
- **WHEN** the user searches `started:2026-10-01..*`
- **THEN** entries on or after that local date match
- **AND** adding `started:<2026-11-01` further limits starts to before November's first local day

#### Scenario: Qualifiers are contiguous unquoted tokens
- **WHEN** the user enters `in: notes`, `started: >=2026-10-01`, `started:2026-10-01 .. 2026-10-31`, or `started:"2026-10-01"`
- **THEN** the query shows a syntax diagnostic rather than trimming, joining, or silently reinterpreting those tokens

### Requirement: Date-only operands use local calendar-day boundaries
Date-only operands SHALL use strict Gregorian `YYYY-MM-DD` notation independent of UI locale and SHALL identify the device's current local calendar day. Let `S(d)` be that local day's start and `N(d)` the following local day's start. A bare date SHALL match `[S(d), N(d))`; `>=d` SHALL mean `>=S(d)`; `>d` SHALL mean `>=N(d)`; `<d` SHALL mean `<S(d)`; `<=d` SHALL mean `<N(d)`. A date range SHALL include both endpoint days. Boundaries SHALL follow calendar days rather than assumed 24-hour durations, matching History's local-day grouping.

#### Scenario: Whole-day comparison boundaries
- **WHEN** the user searches `started:>2026-10-01`
- **THEN** all starts on October 1 are excluded and matching starts begin at the next local day's start
- **AND** `started:<=2026-10-01` includes all starts on October 1 but none on October 2

#### Scenario: Inclusive date range
- **WHEN** the user searches `started:2026-10-01..2026-10-31`
- **THEN** all starts within both endpoint local days and every local day between them can match

#### Scenario: Daylight-saving transition
- **WHEN** a queried local date spans a 23-hour or 25-hour day
- **THEN** the query includes exactly that calendar day, without losing or including an adjacent hour

### Requirement: Explicit timestamps identify absolute instants
Timestamp operands SHALL use `YYYY-MM-DDTHH:MM:SSZ` or `YYYY-MM-DDTHH:MM:SS±HH:MM`. Seconds and an explicit timezone SHALL be required; timezone-less datetimes, fractional seconds, and missing seconds SHALL be rejected in this version. Timestamp comparisons SHALL act on exact instants: `>` and `<` are strict, `>=` and `<=` include equality, and timestamp range endpoints are inclusive. Date and timestamp endpoints SHALL be normalized by their respective rules when combined in a range; a date upper endpoint includes its whole local day, while a timestamp upper endpoint includes only that exact instant and earlier starts.

#### Scenario: Equivalent offsets
- **WHEN** the user searches `started:>2012-04-19T11:00:00Z` or `started:>2012-04-19T14:00:00+03:00`
- **THEN** both queries return the same entries
- **AND** an entry starting at exactly that instant is excluded while a later start is eligible

#### Scenario: No implicit timestamp timezone
- **WHEN** the user enters `started:>2012-04-19T11:00` or `started:>2012-04-19T11:00:00`
- **THEN** the query is invalid rather than silently receiving a local or UTC timezone

#### Scenario: Timezone changes
- **WHEN** the device timezone changes and History becomes current again
- **THEN** date-only constraints are re-evaluated alongside local-day grouping
- **AND** explicit-timestamp instant comparisons retain their meaning

### Requirement: Time-of-day operands filter clock time on any date
Time-of-day operands SHALL use strict 24-hour `HH:MM` or `HH:MM:SS` notation and SHALL filter by the wall-clock time of the constrained instant in the device's current local timezone, independent of calendar date. `HH:MM` SHALL range `00:00`–`23:59`; `HH:MM:SS` SHALL add seconds `00`–`59`. Comparisons SHALL act on exact wall-clock instants (an operand denotes the start of its minute or second); a bare `HH:MM` SHALL match its whole minute, while a bare `HH:MM:SS` SHALL match its exact second. Inclusive ranges with both endpoints `HH:MM`/`HH:MM:SS` SHALL be exact wall-clock intervals; a range whose end is earlier than its start SHALL wrap across midnight (matching either side). Mixed-kind range endpoints (e.g. a date with a clock time) SHALL be a syntax diagnostic. Time-of-day predicates SHALL combine with date predicates on the same qualifier key using AND (e.g. `started:>=2026-10-01 started:>18:00`).

#### Scenario: Evening entries on any date
- **WHEN** the user searches `walk started:>18:00`
- **THEN** entries whose names or categories contain `walk` and whose local start time is strictly after 18:00 match on every date, and starts at exactly 18:00:00 do not

#### Scenario: Overnight range wraps midnight
- **WHEN** the user searches `started:22:00..02:00`
- **THEN** starts at or after 22:00 and starts before or at 02:00 match, while a noon start does not

#### Scenario: Date and clock time combine
- **WHEN** the user searches `started:2026-10-01 started:09:00..17:00`
- **THEN** only October 1 starts within working hours match

### Requirement: The ended qualifier mirrors started on entry end
`ended:` SHALL accept the same operand kinds, comparisons, ranges (inclusive, open, and overnight-wrapping), and group binding as `started:`, applied to the entry's end instant instead of its start. Date-only operands SHALL use local calendar days of the end; timestamps SHALL be absolute; clock times SHALL use the device-local wall clock of the end. Entries with no end SHALL satisfy no `ended:` constraint. `ended:` SHALL combine with `started:` and text matching using AND within its group.

#### Scenario: Ended date range
- **WHEN** the user searches `ended:2026-10-01..2026-10-31`
- **THEN** entries ending on any October local day match, including entries that started in September

#### Scenario: Entries without an end never match ended
- **WHEN** an entry has no end time and the user searches `ended:<2026-11-01`
- **THEN** that entry does not match

### Requirement: The duration qualifier filters entry length
`duration:` SHALL accept the same comparisons and range forms (inclusive, open; no midnight wrap — an end smaller than its start SHALL be a reversed-range diagnostic) as `started:`, applied to the entry's resolved duration: the stored `durationSeconds` when known, else the start-to-end interval when both are known, using the same resolution as displayed durations. Operands SHALL be one or more contiguous `<integer><unit>` components with units `d` (days), `h` (hours), `m` (minutes), `s` (seconds), in descending order without repeats (e.g. `1h`, `2d5h55m34s`, `2d34s`); any other shape SHALL be a syntax diagnostic. A bare operand SHALL mean exact equality in seconds. Entries with no resolvable duration SHALL satisfy no `duration:` constraint. `duration:` SHALL bind to its group, combine with AND, add no highlights or excerpts, and never be negatable.

#### Scenario: Duration comparisons and ranges
- **WHEN** the user searches `gym duration:>1h` or `gym duration:1m..1d`
- **THEN** only `gym` matches longer than an hour (respectively between a minute and a day, inclusive) appear

#### Scenario: Compound and gapped components
- **WHEN** the user searches `duration:<=2d5h55m34s` or `duration:<=2d34s`
- **THEN** both parse as exact second counts (194134s and 172834s) with skipped units contributing zero

#### Scenario: Entries without a duration never match duration
- **WHEN** an entry has no resolvable duration and the user searches `duration:<1h`
- **THEN** that entry does not match

Known edge: matching uses the displayed (resolved) duration, while day and summary totals sum stored seconds only — a legacy entry with no stored seconds but a computable interval can match a `duration:` query yet contribute zero to its totals.

### Requirement: The has qualifier filters field presence, with negation
`has:` SHALL accept exactly `notes` or `category`, as one contiguous unquoted token. `has:notes` SHALL match entries whose notes are non-empty under the existing notes-indicator rule (whitespace-only counts as empty). `has:category` SHALL match entries with at least one attached category id. A `-` prefix SHALL negate exactly these two forms (`-has:notes`, `-has:category`); negation of any other qualifier (`-started:`, `-ended:`, `-in:`) SHALL produce a syntax diagnostic, as SHALL `has:` with any other value, a value list, or a quoted value. `has:` constraints SHALL bind to their group and combine with AND.

#### Scenario: Presence and absence
- **WHEN** the user searches `has:notes -has:category`
- **THEN** only uncategorized entries with non-empty notes match

#### Scenario: Unsupported negation is an error
- **WHEN** the user searches `gym -started:2026-10-01`
- **THEN** the query shows a syntax diagnostic rather than excluding October entries

### Requirement: Non-empty results retain History groups and matching totals
Valid non-empty queries SHALL display each matching entry once, in the existing start-day groups and newest-first ordering, without relevance ranking. Days without matching entries SHALL be omitted. Each displayed group's total SHALL sum only its matching entries, retaining the known-duration-only rule, and SHALL use a localized “matching” label instead of “tracked”. These rules SHALL also apply to date-only or scope-only non-empty queries; a text term is not required to enter filtered presentation.

#### Scenario: Filtered group total
- **WHEN** a day contains 8 hours of entries but only a 30-minute entry matches
- **THEN** its result group shows 30 minutes with the localized “matching” label rather than 8 hours tracked

#### Scenario: No empty sections or duplicate entries
- **WHEN** an entry matches both its name and notes and no entry matches on another day
- **THEN** the entry appears once in its original day group and the other day has no header

### Requirement: Result summaries state match counts and total duration
Valid non-empty queries with at least one match SHALL show a summary directly above the first result group (below the search field), scrolling with the list, stating the number of matching entries and their combined known-duration total. The total SHALL follow the same known-duration-only rule as day totals (entries without a known duration contribute zero) and the same device-locale duration formatting. Counts SHALL use localized plural rules. Blank queries, invalid queries, and valid queries with zero matches SHALL show no summary. Per-day “matching” group totals remain unchanged beneath it.

#### Scenario: Summary counts and totals
- **WHEN** a query matches 3 entries with known durations of 30, 45, and 0 minutes (one in-progress)
- **THEN** the summary states 3 matching entries and a 1h 15m total in the device locale with correct plurals

#### Scenario: No summary outside results
- **WHEN** the query is blank, invalid, or matches nothing
- **THEN** no summary is shown

### Requirement: Highlights explain only in-scope positive text matches
Non-empty results SHALL highlight matching text occurrences only in the selected textual fields. Highlighting SHALL preserve original casing and content, use a semantic contrasting background plus emphasis rather than color alone, and remain legible in light/dark appearances and accessibility contrast settings. Qualifier syntax, source labels, timestamps, durations, icons, and out-of-scope fields SHALL NOT receive highlights. Date-only and scope-only queries SHALL show no text highlights. Highlight formatting SHALL NOT split a row into separate accessibility elements or add spoken formatting markers.

#### Scenario: Default-scope highlight only
- **WHEN** `gym` appears in an entry's name, categories, and notes and the query is `gym`
- **THEN** only the name and category occurrences are highlighted and no notes excerpt appears

#### Scenario: Category highlight
- **WHEN** a query matches a category name using `in:categories`
- **THEN** matching text in that category's visible caption is highlighted without highlighting provenance text

### Requirement: Notes matches reveal bounded contextual excerpts
A result SHALL add a localized `Notes:` excerpt only when notes are selected and contain a positive text-term match. The excerpt SHALL be plain text around the earliest notes occurrence of any query term, with surrounding context rather than an unrelated note prefix. It SHALL preserve original casing, collapse display whitespace and line breaks without editing saved notes, highlight visible in-scope matches, and show ellipses only at ends where content was omitted. It SHALL target at most two visual lines at text sizes below `.xxLarge` while respecting Dynamic Type, relaxing the cap at `.xxLarge` and up so the focal match retains visible context. It SHALL handle non-Latin text and composed characters without splitting them. Existing notes indicators and whole-row tap behavior SHALL remain unchanged. The row's single accessibility label SHALL include the displayed plain-text excerpt, not the full hidden note.

#### Scenario: Match deep inside a note
- **WHEN** `squats in:notes` matches well after the beginning of an entry's note
- **THEN** its row adds a short excerpt around `squats`, highlights that occurrence, and indicates omitted surrounding text with appropriate ellipses

#### Scenario: Notes are not searched by default
- **WHEN** the query `gym in:name` matches an entry whose notes also happen to contain the same text
- **THEN** its notes remain hidden except for the existing notes indicator

#### Scenario: Plain text and accessibility
- **WHEN** a matching note contains Markdown punctuation, newlines, emoji, or CJK text
- **THEN** the excerpt displays literal text with collapsed display whitespace and intact characters
- **AND** VoiceOver reads its displayed text as part of the single row label

#### Scenario: Notes excerpts read as notes, not categories
- **WHEN** one result matches via its categories and another via its notes
- **THEN** the notes result carries the distinct notes treatment (glyph and/or type styling) while the category result shows only caption highlights
- **AND** VoiceOver identifies the excerpt as notes content

### Requirement: Query errors are distinct from no matches
Qualifier keys and field identifiers SHALL be stable lowercase English syntax in every UI locale. Unknown qualifiers or scopes, empty qualifier values or scope-list elements, empty/whitespace-only quoted phrases, unclosed quotes, unsupported quoted escapes, malformed/nonexistent dates, malformed clock times, malformed durations, mixed-kind range endpoints, reversed ranges (including duration ranges whose end is smaller than their start), a range with both endpoints `*`, leading/trailing/doubled `AND`/`OR`, parentheses, negated qualifiers other than `-has:notes`/`-has:category` SHALL produce a localized syntax diagnostic while preserving the query for correction. The diagnostic's explanatory copy and syntax examples SHALL be localized through `L10n` in all five locales like all other user-facing strings; only the qualifier keywords themselves (`in`, `started`, `ended`, `duration`, `has`, `AND`, `OR`, field identifiers) stay English. Incomplete recognized syntax while typing SHALL use that same correctable state. Invalid queries SHALL show neither normal unfiltered History nor stale results represented as matches. A valid query with zero matches SHALL show a distinct localized no-results state with a clear-query action whose bottom spacing from the keyboard SHALL equal the compact-timer clearance even when no timer is running. A genuinely empty History with a blank query SHALL retain its existing empty state. Quoted text containing a colon SHALL be searchable literally rather than interpreted as a qualifier.

#### Scenario: Invalid or incomplete qualifier
- **WHEN** the user enters `in:`, `in:source`, `started:2026-02-30`, or an unsupported `source:healthkit`
- **THEN** no result rows are displayed and a localized syntax explanation distinguishes the query from a valid query with no matches

#### Scenario: Valid query with no matches
- **WHEN** a syntactically valid query matches no committed entry
- **THEN** History shows the no-results state, not the ordinary empty-History message, and clearing the query restores normal History

#### Scenario: Literal qualifier-like name
- **WHEN** the user searches `"project:alpha"`
- **THEN** that text is searched as a literal phrase in the selected fields

### Requirement: Search composes with History lifecycle and account isolation
The query SHALL survive same-account tab switches, entry/Profile navigation, local reloads, sync completion, and undo. Updated entries and category names SHALL be re-evaluated; results, highlights, excerpts, groups, and matching totals SHALL reflect the current snapshot. Search state and derived data SHALL reset on account change/sign-out and SHALL NOT be persisted across app launches or sent to logging/analytics. Row taps SHALL keep the existing editable-manual/read-only-imported form behavior. Log Time, provenance labels, compact timer, nav-bar access, existing undo eligibility, and sync-only pull behavior SHALL remain intact; sync SHALL never be narrowed by the user query. No-match and invalid-query states SHALL offer no pull gesture.

#### Scenario: Editing removes a match
- **WHEN** the user edits a matching entry so it no longer satisfies the query and returns to History
- **THEN** the query remains and the entry disappears from results with groups and totals recomputed

#### Scenario: Reload and undo preserve the query
- **WHEN** sync changes entry/category data or an eligible deletion is undone
- **THEN** the current query is re-applied without being cleared and only currently matching entries appear

#### Scenario: Account isolation
- **WHEN** the user signs out or switches accounts after searching sensitive notes
- **THEN** no prior query, result, or excerpt is carried into the next account's History
