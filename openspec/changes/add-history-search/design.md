## Context

See `proposal.md` for motivation, scope, and the research bundle. The new `history-search` spec defines the query contract; the `history-entry-list` delta defines its integration with existing History behavior.

Current seams at base `a038829`:

- `Features/AppShell/ViewModels/HistoryViewModel.swift` loads `LocalStore.entries()` and categories, builds `categoriesByID`, and derives `DayGroup` values with `makeDayGroups`. It currently discards the ungrouped snapshot after loading.
- `Features/AppShell/Views/HistoryView.swift` owns a stable list/empty/loading container, sync-exit reloads, undo registration, alerts, and entry-form navigation. Search must not put lifecycle modifiers on a newly changing conditional branch.
- `Core/Design/Components/EntryRow.swift` is the shared presentational Variant H row: name/duration, category/provenance/timeframe caption, and a notes-presence icon. Notes content is not currently visible. Provenance is display-only for search.
- `AppShellView.historyStack` owns the existing History navigation stack, `[+]`, Profile, and bottom compact-timer inset. `RootView` recreates account-bound shell state, so query state must remain within that lifecycle.
- Data is already local and account-bound. `LocalStore` remains the sole mutation chokepoint; search needs no mutation, SQL, schema, or relay changes. Current FURPS offline, localization, HIG, provenance, undo, and 60-fps scrolling constraints remain in force.

## Goals / Non-Goals

**Goals:** Keep a single source of entry/category data and one grouping pipeline; separate parsing, evaluation, and presentation; keep query errors explicit; retain original-string match locations for correct highlighting and snippets across all five locales.

**Non-Goals:** No persisted search state, query telemetry, alternate corpus, activity entity, search index, or third-party parser. No ranking pipeline or separate search navigation stack. The proposal lists user-facing exclusions, including autocomplete and full GitHub-language parity.

## Decisions

### 1. Derive search from the existing account snapshot

Cache the loaded ungrouped entries and category dictionary in `HistoryViewModel`. Add an in-memory query string and a derived state distinguishing blank, invalid, valid-with-results, and valid-with-no-results. Recompute matching entries and match metadata when the query, snapshot, or calendar/timezone context changes, then feed only matching entries to the existing `makeDayGroups` helper. Keep the known-duration sum unchanged; choose the localized tracked/matching format from query state rather than modifying stored durations.

All existing create/edit/delete/undo/sync reload paths replace the snapshot and re-apply the **latest** query. A load must not publish results from an earlier captured query over newer typed text. Preserve the existing loading guard and stable lifecycle container. Do not add an explicit local reload to pull-to-refresh; its existing cycle-exit path remains the sole refresh. A query controls rendering only, never outbox drain or delta pulls.

**Alternatives:** New SQL/FTS would add Unicode/tokenizer semantics, another read API, and indexing without evidence of need. A second search-only list/data loader would duplicate grouping and reload behavior and weaken blank-query parity. Both are rejected.

### 2. Use a small pure parser and evaluator

Introduce app-owned, testable types under `Features/AppShell/Models/` (for example `HistorySearchQuery`, `HistorySearchParser`, `HistorySearchEvaluator`, and immutable match-presentation values). Names/file splits are implementation details, not new application layers. Parsing is independent of the store and views; evaluation receives a snapshot and injected calendar/timezone context.

The scanner must recognize quoted spans and their escapes before splitting on unquoted whitespace, and split each resulting qualifier token at its **first** unquoted colon so timestamp colons remain in the operand. A qualifier and its complete value must be one contiguous unquoted token: do not trim a separated value, join a spaced range, or accept quoted qualifier values. Uppercase `AND`/`OR` tokens delimit groups (never text); lowercase variants stay text. Empty operands/list elements and standalone unquoted `..` are diagnostics, not fallback text terms. Produce a typed query as an alternation (OR) of conjunction (AND) groups: text terms, a union of selected fields (global `in:`), and conjunctive start/end/presence predicates bound to their group. Retain source spans for diagnostics. Do not use regex evaluation or rewrite the query on the user's behalf.

Grammar decisions close previously unspecified edges:

| Concern | Decision |
|---|---|
| Default scope | Names + categories union; explicit scopes replace it globally |
| Multiple scopes | Commas or repeated `in:` clauses form a union |
| Several terms | AND across terms within a group; each term can match any selected field |
| Groups | Whitespace/`AND` conjunction, `OR` alternation, `AND` binds tighter, no parentheses |
| Operators | Uppercase `AND`/`OR` only; lowercase and quoted forms are text |
| Presence | `has:notes`/`has:category`, negatable as `-has:`; no other negation |
| Time matching | Case-insensitive Unicode-aware substring; no extra accent folding |
| Phrases | Double quotes; escaped quote/backslash; apostrophes remain literal |
| Scope without text | Valid; selects fields but imposes no “has notes/category” constraint |
| Fixed syntax | Lowercase English keys/fields; values and notes can use any locale |
| Unknown/unfinished syntax | Correctable localized diagnostic; no ignored constraints or stale “matching” rows |
| Literal colons | A quoted phrase can contain colon text without becoming a qualifier |
| Not supported | Field-value aliases (`notes:...`), negation except `-has:`, parentheses, regex, source/duration qualifiers |

**Alternative:** Silently ignoring malformed/unknown qualifiers can display a broader set than the user requested and falsely imply a date constraint was applied. Reject it. Syntax diagnostics are not autocomplete and must not insert completions or values.

### 3. Normalize dates to explicit bounds without 24-hour arithmetic

Parse strict Gregorian ASCII date notation, independent of localized display formats, using the device's current timezone for date-only operands. Translate each date comparison to lower/upper start instants using the spec's `S(d)`/`N(d)` definitions. Use calendar next-day operations, not a fixed number of seconds. Continue using History's existing local calendar grouping/label presentation.

Parse full-second timestamps only when a `Z` or numeric offset is present; preserve their absolute meaning. `>`/`<` remain strict comparisons, not minute/second buckets. Bare timestamp equality does not truncate the stored start. Inclusive timestamp upper bounds and exclusive next-day upper bounds must remain distinguishable in the typed predicate; do not subtract an arbitrary millisecond. Mixed endpoint ranges normalize each operand by its own rule. Validate real dates, chronological ranges, and overflow rather than allowing lenient normalization.

Parse `HH:MM`/`HH:MM:SS` operands as wall-clock filters evaluated against the device-local clock time of the constrained instant. Compare exact wall-clock instants (operand = start of its minute/second); bare `HH:MM` covers its minute, bare `HH:MM:SS` its second. Overnight ranges (end earlier than start) match either side of midnight. `ended:` reuses all operand rules against the entry end; entries with no end satisfy no `ended:` constraint.

Parse `duration:` operands as contiguous `<integer><unit>` components (`d`/`h`/`m`/`s`, descending, no repeats) summed to exact seconds; skipped units contribute zero. Reuse the displayed-duration resolution (stored seconds else start-to-end interval); entries with no resolvable duration satisfy no `duration:` constraint. Bare operands mean exact-second equality; ranges are inclusive with no wrap (smaller end = reversed diagnostic).

Observe significant local calendar/timezone changes and rederive on foreground/re-entry so a still-open date query stays aligned with History grouping. Inject calendar/timezone in tests. Reuse the formatter-serialization discipline added by the current History date-formatting fix; do not introduce unsynchronized shared formatters.

**Alternatives:** Treating date-only values as UTC would disagree with History days. Assigning an implicit zone to timezone-less timestamps would hide ambiguity. Rounding timestamp predicates or using fixed 24-hour days would produce incorrect boundary/DST matches. All are rejected.

### 4. Keep one always-visible inline field on the History root

Attach native `.searchable(text:placement:prompt:)` unconditionally to the History root within its existing navigation stack, with `.navigationBarDrawer(displayMode: .automatic)` so the system pins it with the list and hides it on scroll-down, exactly like Settings/Mail. There is no activation button and no `isPresented` driving: the modifier is never added or removed, so opening/typing/closing search performs no structural layout change. No programmatic focus hacks — the user taps the field; the system animates the drawer and keyboard.

Do not attach search suggestions or completion APIs; disable automatic capitalization/correction and smart punctuation that could rewrite manually entered qualifier syntax. The localized prompt explains that names are the default scope; a compact static syntax hint can accompany a syntax diagnostic (not a suggestion list). No separate help screen or discovery panel is introduced. The bottom tab bar hides only for non-blank queries (results, no-matches, syntax diagnostics) with an animated transition, and stays visible for a blank query — so focusing the empty field performs no structural change and the keyboard covers the bar while typing per system behavior. The `.searchable` modifier itself is never added or removed. The clear-query action keeps timer-equivalent bottom clearance with and without a running compact timer.

Do not attach search suggestions or completion APIs; disable automatic capitalization/correction and smart punctuation that could rewrite manually entered qualifier syntax. The localized prompt explains that names are the default scope; a compact static syntax hint can accompany a syntax diagnostic (not a suggestion list). No separate help screen or discovery panel is introduced.

**Alternatives:** A custom text field would add keyboard/focus/clear-button behavior the native control already provides. A new Search tab or pushed result screen would duplicate History and violate the single in-place list approach. Prefer the native root-scoped field, with iOS 18 and iOS 26 behavior verified rather than assuming placement from training data.

### 5. Pass immutable match presentation into the existing row

Keep `EntryRow` presentational, with one optional search-presentation input whose absence takes its existing rendering path. It holds original-string match ranges for the name and individual category display names, plus an optional notes excerpt and its ranges. Produce it during derivation, not in row `body`. Preserve original `TimeEntry` values, row IDs, icon alignment, durations, timeframes, provenance, and whole-row tap handling. Do not change the name-picker's prefix matching or shared entry identity rules.

Extract a small reusable `SearchHighlightedText` presentation helper rather than forking the entire row. Use native text runs with a custom match attribute and `TextRenderer` for background drawing, plus emphasis on matched runs. Limit this renderer to highlighted text rather than installing it over the whole screen. Keep text layout/accessibility native; do not render HTML, rasterize text, or build per-character stacks. Resolve Theme styling at render time so appearance/contrast changes do not require reparsing. Prefer an existing semantic accent wash plus emphasis; introduce a documented semantic match-background token only if contrast verification shows it is needed.

Compute matching ranges against the original strings with a consistent case-insensitive policy. Never lowercase a copy and reuse its integer offsets: Unicode case mappings can change length. Merge overlapping display ranges. Match each category separately, then offset its display ranges when composing the comma-separated caption; provenance text has no search ranges. Keep visible note text and its match mapping together after whitespace normalization.

**Alternative:** A separate `SearchResultRow` would duplicate nearly all Variant H layout, provenance, timing, and accessibility rules now that grouping and ordinary History rows are retained. A single optional presentation value plus dedicated text/excerpt helpers gives a smaller regression surface. Keep blank-query parity under regression tests.

### 6. Show one bounded notes excerpt, only when it explains a match

Generate at most one excerpt per entry, centered on the earliest positive notes occurrence in a selected notes field. Use surrounding grapheme-safe context; prefer whitespace boundaries where available without assuming space-delimited languages. Collapse display whitespace with an original-to-display location mapping, then compute/translate highlight ranges for the excerpt. Add leading/trailing ellipses only for omitted content. Preserve the first complete matching term even if it exceeds the usual context budget.

Place a localized `Notes:` excerpt below the two normal row lines. Target two lines at ordinary sizes, shortening context rather than hiding the focal match; allow layout to expand at accessibility sizes when necessary. Do not use a fixed row height or shrink text to fit. The excerpt SHALL carry a visual treatment that distinguishes it from the category caption at a glance (dedicated notes glyph and/or distinct type styling, Theme-only, defined in `Design/COMPONENTS.md`): a notes match must never read as a category match. Read only the displayed excerpt in the row's single accessibility label, retaining the existing “has notes” affordance and identifying the excerpt as notes content; do not read omitted note content or announce formatting markers.

**Alternatives:** Showing notes for every result exposes content unnecessarily and destroys density. Showing a note prefix can hide the actual match. Multiple separate snippets per note add complexity and height; later occurrences can be examined in the existing entry form. These are excluded from v1.

### 7. Keep state local to the account-bound History lifecycle

Keep the query on the existing History view-model lifecycle, not in defaults, scene restoration, shared static state, backend calls, or telemetry. Preserve it during same-account reloads and entry navigation. Native search cancellation must not silently clear it just because a destination is pushed. The existing account-bound shell remount resets query/snapshots on sign-out/account change; verify that assumption with a regression test rather than relying on it implicitly. A cold launch begins blank.

Distinguish no local entries with a blank query, valid no matches, and invalid syntax. Keep search and clear actions available in each state. Populated results keep sync-only pull; invalid/no-match states do not add a pull gesture. Undo remains account/resource-scoped and can restore an entry even if it does not match the active query; it must not clear the query or broaden results.

**Alternative:** Persisting queries or logging parse failures with raw input risks leaking private note content and carrying context across accounts; no such persistence or telemetry is needed.

### Research references and implementation pin

The topic/HIG queries, source URLs, lookup date, and external-library waiver are recorded in `proposal.md` and constrain this design. Apple lookup ID: `/websites/developer_apple_swiftui`, pin **iOS 18 SDK via Xcode 16+**:

- `Scope searchable(text:placement:prompt:) to a NavigationStack root list and use navigationBarDrawer placement on iOS 18 SDK via Xcode 16+ without adding search suggestions` → [Adding a search interface](https://developer.apple.com/documentation/swiftui/adding-a-search-interface-to-your-app), [navigationBarDrawer(displayMode:)](https://developer.apple.com/documentation/swiftui/searchfieldplacement/navigationbardrawer(displaymode:)).
- `Highlight matching text ranges with a background using TextRenderer and custom TextAttribute on iOS 18 SDK via Xcode 16+ while preserving Text accessibility and Dynamic Type` → [textRenderer(_:)](https://developer.apple.com/documentation/swiftui/view/textrenderer(_:)), text-layout custom attribute lookup, and renderer drawing references. Restrict implementation to symbols confirmed at the iOS 18 floor; the current index also contains newer APIs and mixed availability metadata.

Reconfirm exact SDK signatures/availability during apply, including Foundation date/string APIs chosen then; do not copy unverified generated examples or lift the deployment target. No newer attributed-text editing APIs are needed.

## Risks / Trade-offs

- **A query language without autocomplete is less discoverable** → Explain the default scope in the prompt, give concise diagnostics/static examples, and document syntax; no suggestion engine sneaks into scope.
- **Malformed text transiently hides results while typing** → Keep the entered query and an explanatory correctable diagnostic visible; never imply ignored filters were applied. Test IME/composed input.
- **Native search changes navigation/header chrome across OS versions** → UI-check root placement, pushed destinations, permanent actions, pinned headers, keyboard, and compact-timer clearance on iOS 18/26 and iPhone/iPad.
- **Unicode highlights or snippet clipping can point at the wrong text** → Original-string range tests, composed/emoji/CJK fixtures, and accessibility-size UI checks with the focal match visible.
- **Notes excerpts reveal previously hidden content** → Only show when notes are explicitly in scope and contain a matching term; never persist/log query, excerpt, or raw note; preserve normal History privacy.
- **Per-keystroke scanning of long notes could block UI** → Parse once and derive each entry's match metadata once per query/snapshot, with lazy row rendering; measure a representative thousands-entry corpus. If measurement requires background derivation, keep it cancellable/latest-query-wins without changing the contract or adding partial-corpus results.
- **Full timestamp equality is precise, not a seconds-wide search bucket** → Document it and test subsecond stored starts; users can use comparisons/ranges for a window.
- **Existing baseline prose includes legacy form-presentation wording** → Preserve the current pushed entry-form implementation and entry-editor contract; do not turn this feature into an unrelated navigation repair.

## Migration Plan

No migration, index, new dependency, API contract, or backend deployment is required. Ship the iOS-only feature with local query state initially blank. Rolling back the iOS code leaves all account files, entries, notes, outbox, cursors, and undo data unchanged. Update durable UI/requirements docs as implementation lands; synchronize the new/modified baseline specs only through the normal completion/archive workflow.
