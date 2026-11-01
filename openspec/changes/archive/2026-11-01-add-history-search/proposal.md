## Why

History has no way to find older entries without scrolling. Issue [#141](https://github.com/AntonKosenkoPro/timeOfLife/issues/141) needs a visually compact but expressive search that works offline and preserves the familiar History presentation.

## What Changes

- Add one always-visible inline native search field to History (navigation drawer, hides on scroll), without autocomplete, suggestions, token chips, activation modes, or a separate filter panel. The bottom tab bar hides with animation while a query is active and returns for a blank query.
- Default text search covers entry names and category names (`gym` equals `gym in:name,categories`); `in:name`, `in:categories`, and `in:notes` narrow the scope with comma-separated unions and quoted phrases. Uppercase `AND`/`OR` combine match groups (`AND` binds tighter, no parentheses); `has:notes`/`has:category` with `-has:` negation filter field presence.
- Add GitHub-inspired `started:`/`ended:`/`duration:` comparisons and inclusive/open-ended ranges over dates, absolute timestamps, wall-clock times, and durations. Date-only operands mean local calendar days; full timestamps require seconds and `Z` or an explicit UTC offset and identify absolute instants; clock-time operands (`HH:MM`/`HH:MM:SS`) filter wall-clock time on any date; duration operands use contiguous `d`/`h`/`m`/`s` components.
- Keep blank-query History unchanged. Non-empty valid queries narrow committed entries locally while retaining start-day groups and newest-first ordering; group totals count only matches and use a localized “matching” label.
- Highlight positive text matches only in searched fields. Show a short, highlighted plain-text notes excerpt only when notes are in scope and contain a match.
- Distinguish invalid/incomplete syntax, valid queries with no matches, and a genuinely empty History. Preserve the query across same-account reloads, navigation, and tab switches; do not persist it across app launches or account changes.

## Capabilities

### New Capabilities

- `history-search`: Local query grammar and evaluation, date/time boundaries, search lifecycle, scoped match presentation, excerpts, and diagnostics.

### Modified Capabilities

- `history-entry-list`: Search narrows the committed-entry list without changing its grouping or navigation; day totals switch between full-day “tracked” and filtered “matching”; result rows can add scoped highlights and notes excerpts without changing blank-query rows.

## Impact

- iOS only: `HistoryView`, `HistoryViewModel`, a pure parser/evaluator and match-presentation model, reusable row text/highlight presentation, semantic `Theme` styling, and tests. Existing `LocalStore.entries()` and category snapshots remain the data source; no SQL/search index, schema migration, backend endpoint, OpenAPI, sync, or new dependency changes.
- New user-facing strings go through `L10n` and all five locales (`en`, `ru`, `zh-Hans`, `es-419`, `pt-BR`). Implementation updates `Design/COMPONENTS.md` first for new presentation components, then `Design/SCREENS/History.md`, relevant design decisions/interactions, FURPS, README, and `docs/project-context.md`.
- Preserved contracts: account-bound/offline data, entry provenance, EDIT/LOCKED entry-form navigation, Log Time, compact timer, persistent navigation bar, sync-only pull-to-refresh, existing reload triggers, and shake-to-undo.
- Non-goals: autocomplete of any kind, saved/recent searches, relevance ranking, flat results, a separate search tab, source/duration filters, hidden-source-label matching, regex/parentheses/other negation beyond `-has:`, full GitHub syntax parity, and changes to other screens or timer drafts.

### Research basis

Research fetched during this exploration/proposal on 2026-10-30; implementation must reconfirm applicability:

- Topic: Context7 `/github/docs`, query `Non-code search query syntax: quoted phrases, qualifier:value, negated qualifiers, numeric comparisons and date ranges`; checked against the owner-provided [GitHub search syntax guide](https://docs.github.com/en/search-github/getting-started-with-searching-on-github/understanding-the-search-syntax). Borrow the documented date/offset/range notation, not undocumented GitHub behavior or its entire language.
- HIG: `/websites/developer_apple_design_human-interface-guidelines`, query `Presenting search results: relevance, context snippets, emphasizing matched text, and distinguishing an empty search field from no matching results`; [search-fields](https://developer.apple.com/design/human-interface-guidelines/search-fields) supports a clearly scoped search and immediate refinement. Suggestions are optional and explicitly deferred here.
- Apple API: `/websites/developer_apple_swiftui`, query `Scope searchable(text:placement:prompt:) to a NavigationStack root list and use navigationBarDrawer placement on iOS 18 SDK via Xcode 16+ without adding search suggestions`; pin: **iOS 18 SDK via Xcode 16+**, using APIs available at that floor, with iOS 26 UI regression coverage.
- External-library/setup best-practice item waived: no additional library/service or database query behavior; the parser/evaluator is pure app-owned logic over already-loaded snapshots.
