## 1. Confirm research and the current baseline

- [x] 1.1 Before implementation, reconfirm the research bundle cited in `proposal.md`/`design.md`: GitHub non-code query syntax (`/github/docs`), HIG local search/results (`/websites/developer_apple_design_human-interface-guidelines`), and native search plus text highlighting (`/websites/developer_apple_swiftui`, iOS 18 SDK via Xcode 16+). Fetch current docs for the Foundation date/string APIs actually chosen; record queries/IDs/pins and the no-new-library waiver, keeping each lookup focused and within repo lookup budgets.
- [x] 1.2 Fetch/rebase the worktree on fresh `origin/main` before code changes and re-check History source/contracts. Record blank-query baseline behavior/screenshots outside git: groups, total labels, rows/notes icons, persistent toolbar, compact timer, entry-form push, and sync/undo. This is a new feature, not a bugfix; do not claim an unrecorded bug reproduction.
- [x] 1.3 Re-read relevant FURPS rows (Common U1–U5/S2/S5, Timetracking local-first/pull/provenance/manual-entry/undo, Activity_Catalog_and_Categories exact-text identity and History scrolling performance). Resolve any actual conflict in the change artifacts before coding; retain the single-LocalStore-mutation and no-backend-change boundaries.

## 2. Build and test the pure query language

- [x] 2.1 Add a small pure query model/scanner/parser with source-located diagnostics. Cover whitespace, double-quoted phrases and escaped quotes/backslashes, default name scope, global comma/repeated scope unions, term AND/field OR, literal quoted colons, and valid scope-only/date-only queries.
- [x] 2.2 Implement strict `started:` operands and typed predicates for bare operands, `>`/`>=`/`<`/`<=`, inclusive and open ranges, and multiple conjunctive bounds. Keep date-only local calendar boundaries separate from absolute full-second explicit-offset timestamps; never round stored starts or assume 24-hour days.
- [x] 2.3 Add parser/diagnostic tests for unknown qualifiers/scopes, empty values/list elements/quoted phrases, unclosed quotes/invalid escapes, separated qualifier operands, quoted qualifier values, spaced range operators, bad dates/offsets, missing seconds/timezone, unsupported fractional timestamps, reversed/malformed ranges, and `*..*`. Confirm contradictory but individually valid predicates produce no matches rather than silently dropping constraints.
- [x] 2.4 Add date-boundary tests for all operators, both range endpoints, open/mixed ranges, exact/subsecond timestamps, equivalent positive/negative offsets and `Z`, month/year/leap-day edges, local midnight, start-versus-overlap, DST spring/fall days, non-default UI locale/calendar, and timezone changes.

## 3. Derive matches and bounded match context

- [x] 3.1 Implement case-insensitive Unicode-aware substring evaluation over entry names, all attached category names, and raw plain-text notes using only selected fields. Preserve case-sensitive entry identity and accent distinctions, require every term, combine start constraints with AND, exclude drafts, and emit each matching entry once.
- [x] 3.2 Compute and merge original-string highlight ranges once per derivation. Test overlapping/repeated matches, composed/decomposed characters, non-Latin scripts, emoji, case mappings with different lengths, every category position, comma-composed captions, and provenance/out-of-scope exclusion; do not apply lowercased-string offsets to original strings.
- [x] 3.3 Implement one notes excerpt around the earliest in-scope notes hit with bounded grapheme-safe context, display-whitespace collapsing and range mapping, and ellipses only for omitted text. Test beginning/middle/end hits, multiple distant terms, very long terms, short/untruncated notes, multiline literal Markdown, CJK and emoji, and cases with no notes scope or no notes hit.
- [x] 3.4 Integrate query/derived state with the existing History view model's entry/category snapshot and `makeDayGroups`, preserving original entries/IDs, the known-duration total rule, and the stable reload guard. Test blank-query parity, whitespace-only parity, omitted empty days, matching totals, one-row deduplication, and latest-query-wins when a reload finishes.

## 4. Integrate the compact History UI

- [x] 4.1 Document the reusable highlight/excerpt presentation contract in `Design/COMPONENTS.md` before implementing it. Add one optional immutable search-presentation input to `EntryRow` with an unchanged nil/blank path, native text-run highlight rendering, Theme-only contrasting background plus emphasis, and the conditional excerpt beneath the normal two row lines.
- [x] 4.2 Add the native History-root search field, query binding, localized name-default prompt, clear/cancel handling, and syntax-safe input configuration. Do not add any autocomplete, qualifier/value suggestions, recent queries, date picker, token chips, scope bar, or filter panel; keep search off pushed destinations.
- [x] 4.3 Add explicit blank/invalid/valid-no-matches/results rendering without attaching lifecycle modifiers to conditional branches. Keep the field available in all states; use a correctable syntax diagnostic and distinct no-results state with clear action; populated results retain sync-only pull and empty/invalid states add no pull.
- [x] 4.4 Switch day-header formatting between the existing full-day “tracked” label for blank queries and filtered “matching” for valid non-empty queries. Retain day labels, pinned/in-list two-line headers, icon alignment, provenance, timeframe/duration, `[+]`, Profile, and bottom compact-timer clearance.
- [x] 4.5 Add all prompts, total formats, diagnostics, no-results/clear copy, and `Notes:` labeling through `L10n` in all five locales (`en`, `ru`, `zh-Hans`, `es-419`, `pt-BR`), updating localization-key coverage. Preserve one accessibility element per row, existing notes-presence speech, displayed-excerpt speech only, stable row IDs, and accessible field/error/clear controls.

## 5. Preserve lifecycle, account isolation, and performance

- [x] 5.1 Add integration tests showing query retention/re-evaluation across tab switches, entry/Profile navigation, create/edit/delete, category rename/delete, sync completion/failure, and eligible undo. Verify non-matching changes remain hidden, matching entries re-bucket/re-total correctly, no new row actions appear, and EDIT/LOCKED behavior is unchanged.
- [x] 5.2 Verify the query and derived results reset on sign-out/account change and cold launch; keep queries/excerpts out of persistent storage, network requests, analytics, and logs (including parser errors). Re-evaluate local-day predicates/grouping on foreground and timezone/calendar change without altering absolute timestamp predicates.
- [x] 5.3 Measure representative thousands-entry text/notes searches and result-list scrolling. Parse once per query and derive once per entry/snapshot, never in row bodies; if measured UI work requires background derivation, use cancellable latest-query-wins results without a partial corpus or stale highlights. Record measurement context and findings outside binary git artifacts.

## 6. Verify the shipped presentation and compatibility

- [x] 6.1 Run the full backend verification (`gofmt -l .` empty, `go vet ./...`, `golangci-lint run`, `go test ./...`) on a dedicated backend agent in parallel with iOS verification. No backend/API code changes are expected; report any unrelated failure rather than silently claiming green.
- [x] 6.2 On a separate iOS agent, run strict SwiftLint, warning-clean simulator build, focused new tests followed by the full iOS suite per `docs/ios-test-loop.md`. Use one `xcodebuild`/simulator at a time; run XcodeGen only if managed project inputs change and never concurrently with project edits.
- [ ] 6.3 Perform interact/screenshot verification on iOS 18 and iOS 26, including iPhone and an iPad layout: blank-query parity against baseline, scoped highlights, notes-only/multi-field matches, excerpt clipping, tracked/matching totals, date-only results, no matches, invalid/incomplete syntax, and no autocomplete. Use the applicable Argent skills and screenshot-diff workflow; keep screenshots/videos/xcresults outside git.
- [ ] 6.4 Verify light/dark, Increase Contrast/Reduce Transparency, large/accessibility Dynamic Type, VoiceOver row labels, CJK/IME and composed text, long localized labels, keyboard/cancel behavior, pushed-form back navigation, persistent `[+]`/Profile access, pinned-header legibility, last-row reachability with the compact timer, and offline/pull/sync/undo behavior. Use a repeatable acceptance flow for the core search scenario and record two consecutive passes if preserving it as QA automation.

## 7. Finalize documentation and handoff

- [x] 7.1 Update `Design/SCREENS/History.md` and its implementation checklist, relevant `Design/INTERACTIONS.md`/`Design/DECISIONS.md`, component/token docs if needed, the applicable FURPS feature row, README, and `docs/project-context.md`. Explain name-default syntax, local-day/absolute-timestamp semantics, scoped excerpts, matching totals, no-autocomplete scope, and unchanged backend contract; do not present proposed behavior as shipped before verification.
- [x] 7.2 Reconcile only the current search-related roadmap/context references without reviving the removed activities layer or changing unrelated deferred work. Do not edit baseline specs directly; retain the two deltas for normal spec sync/archive after completion/human approval.
- [x] 7.3 Run strict validation for `add-history-search`, inspect the implementation diff for out-of-scope changes and binaries, and rebase again onto fresh `origin/main` before PR handoff. Re-run affected checks after rebase; use the normal PR workflow without merging/archiving as part of implementation, and keep all task evidence/status accurate.

## 8. On-device corrections (post-deploy feedback round)

- [x] 8.1 Move search behind a leading navigation-bar search button: field hidden by default, revealed + focused on tap, query cleared and field hidden on close. Update specs/design/tasks evidence and keep no-autocomplete behavior.
- [x] 8.2 Hide the bottom tab bar while search is active and restore it on close; verify last-row reachability and compact-timer clearance in both states.
- [x] 8.3 Give the clear-query action the same bottom keyboard clearance with and without a running compact timer; verify on device with and without the timer.
- [x] 8.4 Localize all syntax-hint and diagnostic example copy through `L10n` in all five locales (qualifier keywords stay English); update snapshot coverage and verify in a non-English locale on device.
- [x] 8.5 Re-run affected SwiftLint/build/tests, strict re-validation, and redeploy the Release build to the connected iPhone; smoke-test corrections 8.1–8.4 on device with screenshots kept outside git.

## 9. Adopt Spike A (device verdict: inline field wins)

Section 8 items 8.1–8.2 are SUPERSEDED by the Spike A hand-test verdict (inline always-visible field feels native; button activation does not). Keep 8.3–8.5 as built.

- [x] 9.1 Remove the navigation-bar search button and all activation state (`isHistorySearchActive`, `isPresented` driving, focus hacks); attach `.searchable` unconditionally with `.navigationBarDrawer(displayMode: .automatic)`; never hide the tab bar for search. Delete now-dead code (button toolbar, conditional-attach helper) rather than leaving it.
- [x] 9.2 Re-verify: SwiftLint `--strict`, warning-clean build, affected suites + full iOS suite per `docs/ios-test-loop.md` (one xcodebuild/simulator at a time); update/remove tests that asserted button-activation behavior; keep blank-query parity and all grammar/highlight/excerpt tests green.
- [x] 9.3 Update `Design/SCREENS/History.md`, component/interaction/decision docs, and FURPS/README/project-context wording that described button activation or tab-bar hiding; keep specs/design/tasks as the source of truth.
- [x] 9.4 Strict re-validate, Release rebuild + devicectl reinstall on Tony's iPhone, on-device smoke test (field pinned, hides on scroll, live filtering, tab bar visible, clear-button clearance with/without timer, localized examples); screenshots outside git. Stop at PR-ready; no merge/PR/archive.

## 10. Hide the tab bar while a query is active (owner decision)

Section 8 item 8.2's intent is RESTORED in narrower form: hide only for non-blank queries, never for focusing the empty field. Section 9's always-visible tab bar behavior is superseded for the non-blank case only.

- [x] 10.1 Drive tab-bar visibility from blank vs non-blank query state with an animated transition; keep `.searchable` always attached and perform no other structural change on the blank↔non-blank transition. Blank query (including focused empty field) keeps the tab bar; results, no-matches, and syntax-diagnostic states hide it.
- [x] 10.2 Re-verify: SwiftLint `--strict`, warning-clean build, affected + full iOS suite; add/adjust tests for tab-bar visibility per query state if testable without a host app change; keep all existing search tests green.
- [x] 10.3 Update the touched wording in `Design/SCREENS/History.md`, interaction/decision docs, FURPS/README/project-context only where they claim the tab bar stays visible; keep specs/design/tasks as the source of truth.
- [x] 10.4 Strict re-validate, Release rebuild + devicectl reinstall on Tony's iPhone, on-device feel test (first keystroke hides with animation, clearing restores, no jump; focus-without-text changes nothing); screenshots outside git. If the transition jumps on device, report the feel honestly rather than checking the box. Stop at PR-ready; no merge/PR/archive.

## 11. Result summaries and notes-excerpt identity (behavior polish)

- [x] 11.1 Implement the scrolling result summary above the first result group (match count with localized plurals + combined known-duration total, same formatting rules as day totals; hidden for blank/invalid/zero-match states) and the visually distinct notes-excerpt treatment (notes glyph and/or distinct type styling, Theme-only; never confusable with category caption highlights). Document the excerpt treatment in `Design/COMPONENTS.md` before implementing it.
- [x] 11.2 Add/adjust unit tests (summary counts/totals incl. in-progress-zero rule, plural forms, no-summary states; excerpt distinction vs category highlights; VoiceOver notes identification) plus any new strings through `L10n` in all five locales with snapshot coverage.
- [x] 11.3 SwiftLint `--strict`, warning-clean build, affected + full iOS suite; update touched docs wording (`SCREENS/History.md`, interactions/decisions, FURPS/README/project-context) only where the summary/excerpt behavior is described.
- [x] 11.4 Strict re-validate and verify on device if reachable (summary correctness, excerpt distinction at a glance, no layout jump from the added summary row), else simulator; screenshots/recordings outside git. Stop at PR-ready; no merge/PR/archive.

## 12. Extended query language (presence, boolean logic, clock times, ended)

- [x] 12.1 Extend the pure parser/evaluator: `has:notes`/`has:category` with `-has:` negation only; explicit uppercase `AND`/`OR` groups (`AND` binds tighter, no parentheses, lowercase forms stay text); `in:` stays global while `started:`/`ended:`/`has:` bind to their group; `HH:MM`/`HH:MM:SS` wall-clock operands (comparisons, inclusive/open/overnight-wrapping ranges, minute-covering bare `HH:MM`, exact-second bare `HH:MM:SS`, same-kind endpoints only); full `ended:` parity with `started:` with nil-end entries matching nothing; new default scope `name,categories` (`gym` ≡ `gym in:name,categories`).
- [x] 12.2 Extend parser/diagnostic/evaluator tests: group binding and precedence, lowercase/quoted operators as text, leading/trailing/doubled operators, parens, unsupported negations, unknown `has:` values, bad clock times, mixed-kind ranges, wrap-around and minute-boundary semantics, `ended:` date/time/clock coverage incl. nil ends, default-scope union behavior and highlight scoping for the new default.
- [x] 12.3 New diagnostics through `L10n` in all five locales with snapshot coverage; SwiftLint `--strict`, warning-clean build, affected + full iOS suite; update summary/VoiceOver behavior if group semantics change what a "match" explains; touch up specs-adjacent docs (`SCREENS/History.md`, interactions/decisions, FURPS/README/project-context) only where the grammar is described.
- [x] 12.4 Strict re-validate and verify on device if reachable (including `walk started:>18:00`-style clock queries and `gym OR run` grouping against real data), else simulator; media outside git. Stop at PR-ready; no merge/PR/archive.

## 13. Duration qualifier (follow-up, queued behind section 12)

- [x] 13.1 Implement the `duration:` qualifier per spec (contiguous `d`/`h`/`m`/`s` components, descending, no repeats, skipped units zero; comparisons, inclusive/open ranges, no wrap; bare operand exact-second equality; displayed-duration resolution; unresolvable durations match nothing; group-bound, AND-combined, no highlights/excerpts, no negation).
- [x] 13.2 Add parser/diagnostic/evaluator tests (component parsing incl. `2d34s`, bad shapes, reversed ranges, exact-equality boundaries, subsecond stored durations, nil-duration exclusion, group binding with text/date constraints).
- [x] 13.3 New diagnostics through `L10n` in all five locales with snapshot coverage; SwiftLint `--strict`, warning-clean build, affected + full iOS suite; touch up specs-adjacent docs only where the grammar is described.
- [x] 13.4 Strict re-validate and verify on device if reachable (`gym duration:>1h`, `duration:1m..1d` against real data), else simulator; media outside git. Stop at PR-ready; no merge/PR/archive.
