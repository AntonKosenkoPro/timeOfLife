## 1. Store queries

- [ ] 1.1 Add `LocalStore.entries(activityID:)` (committed entries for one activity, `started_at DESC`, same `activity_name` join as `entries()`)
- [ ] 1.2 Add `LocalStore.totalDuration(activityID:)` (`SUM(duration_seconds)`, committed only) and unit-test it
- [ ] 1.3 Verify the `entries.activity_id` index covers the per-activity query; add an index in the migrator if needed

## 2. Provenance labels (Q6-b: rows everywhere)

- [ ] 2.1 Add localized "via <Source>" strings (en + ru) and `L10n` cases; add the static `source → localized name` mapping (manual → nil)
- [ ] 2.2 Extend `EntryRow` with a `viaText` input appended to the category caption line; fold into the a11y label builder
- [ ] 2.3 Wire `viaText` into `HistoryViewModel` row presentation; unit-test "via Screen Time" / manual-no-label

## 3. Detail view model + view

- [ ] 3.1 Create `Features/ActivityDetail` with `ActivityDetailViewModel` loading `activity(id:)`, its categories, `entries(activityID:)`, and the total; reuse `HistoryViewModel.makeDayGroups`/`dayLabel`/`naturalDuration`
- [ ] 3.2 Build `ActivityDetailView` sheet: identity header (icon, name, categories), all-time total right-aligned opposite the name in monospaced digits, "Edit activity" button, day-grouped `ScrollView`+`LazyVStack` list of inert rows
- [ ] 3.3 Present `ActivityEditorView` stacked on the detail sheet; reload the sheet after the editor dismisses
- [ ] 3.4 Guard deleted-while-open activity: `activity(id:) == nil` on reload → dismiss the sheet

## 4. History wiring

- [ ] 4.1 Make History rows tappable → present the activity detail sheet (medium detent, draggable to large); no swipe/long-press actions
- [ ] 4.2 Keep History's nav-bar/compact-timer/elevated-header behavior untouched; sheet must not interfere with the scroll-driven header elevation

## 5. Strings, docs, design

- [ ] 5.1 Add all new strings to `en.lproj` + `ru.lproj` + `L10n` (U4): sheet title if any, "Edit activity", "via <Source>" names, total label if needed
- [ ] 5.2 Update `docs/project-context.md` "Incomplete / deferred" (via-labels item delivered on rows; entry-detail wording dropped) and mention the new capability
- [ ] 5.3 Update `Design/COMPONENTS.md` with the detail-sheet component entry if the layout warrants one

## 6. Verification

- [ ] 6.1 Previews: sheet with entries/categories, sheet without categories, row with and without "via" label in both languages
- [ ] 6.2 Unit tests: `totalDuration`, day grouping reuse, provenance formatter, deleted-activity guard
- [ ] 6.3 `swiftlint lint --strict`, `xcodegen generate`, build + full test suite green on a simulator; manually verify tap → sheet → edit → return, and running-timer exclusion