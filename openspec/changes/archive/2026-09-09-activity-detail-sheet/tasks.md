## 1. Store queries

- [x] 1.1 Add `LocalStore.entries(activityID:)` (committed entries for one activity, `started_at DESC`, same `activity_name` join as `entries()`)
- [x] 1.2 Add `LocalStore.totalDuration(activityID:)` (`SUM(duration_seconds)`, committed only) and unit-test it
- [x] 1.3 Verify the `entries.activity_id` index covers the per-activity query; add an index in the migrator if needed

## 2. Provenance labels (Q6-b: rows everywhere)

- [x] 2.1 Add localized "via <Source>" strings (en + ru) and `L10n` cases; add the static `source → localized name` mapping (manual → nil)
- [x] 2.2 Extend `EntryRow` with a `viaText` input appended to the category caption line; fold into the a11y label builder
- [x] 2.3 Wire `viaText` into `HistoryViewModel` row presentation; unit-test "via Screen Time" / manual-no-label

## 3. Detail view model + view

- [x] 3.1 Create `Features/ActivityDetail` with `ActivityDetailViewModel` loading `activity(id:)`, its categories, `entries(activityID:)`, and the total; reuse `HistoryViewModel.makeDayGroups`/`dayLabel`/`naturalDuration`
- [x] 3.2 Build `ActivityDetailView` sheet: identity header (icon, name, categories), all-time total right-aligned opposite the name in monospaced digits, "Edit activity" button, day-grouped `ScrollView`+`LazyVStack` list of inert rows
- [x] 3.3 Present `ActivityEditorView` stacked on the detail sheet; reload the sheet after the editor dismisses
- [x] 3.4 Guard deleted-while-open activity: `activity(id:) == nil` on reload → dismiss the sheet

## 4. History wiring

- [x] 4.1 Make History rows tappable → present the activity detail sheet (medium detent, draggable to large); no swipe/long-press actions
- [x] 4.2 Keep History's nav-bar/compact-timer/elevated-header behavior untouched; sheet must not interfere with the scroll-driven header elevation

## 5. Strings, docs, design

- [x] 5.1 Add all new strings to `en.lproj` + `ru.lproj` + `L10n` (U4): sheet title if any, "Edit activity", "via <Source>" names, total label if needed
- [x] 5.2 Update `docs/project-context.md` "Incomplete / deferred" (via-labels item delivered on rows; entry-detail wording dropped) and mention the new capability
- [x] 5.3 Update `Design/COMPONENTS.md` with the detail-sheet component entry if the layout warrants one

## 6. Verification

- [x] 6.1 Previews: sheet with entries/categories, sheet without categories, row with and without "via" label in both languages
- [x] 6.2 Unit tests: `totalDuration`, day grouping reuse, provenance formatter, deleted-activity guard
- [x] 6.3 `swiftlint lint --strict`, `xcodegen generate`, build + full test suite green on a simulator; manually verify tap → sheet → edit → return, and running-timer exclusion

## 7. Detail sheet redesign (revision: single-appearance header, entry-only rows)

- [x] 7.1 Move activity name to the toolbar title and "Edit activity" to the toolbar; remove the name from the body header so each field appears exactly once
- [x] 7.2 Rework the body header: activity icon leading, "Categories" line with per-category icons, notes when present; add a `Divider` separating the header from the Entries section
- [x] 7.3 Move the all-time total to the Entries section header ("Entries" + "Total: <duration>"); drop the header total opposite the name
- [x] 7.4 Add the pure three-component duration formatter (`w/d/h/m/s`, up to 3, seconds shown with minutes even as `0s`) with unit tests; use it for the total and sheet row durations
- [x] 7.5 Replace `EntryRow` in the sheet with a dedicated entry-only row (time range with day-prefix rule for cross-midnight entries, sync icon + source name, duration); History keeps `EntryRow` + "via" captions
- [x] 7.6 Add the "Categories" label string (en + ru + `L10n`); update `LocalizationTests` count
- [x] 7.7 Update previews (redesigned sheet, entry-only rows with/without provenance, cross-midnight row, both locales) and `Design/COMPONENTS.md` (`ActivityDetailView` entry)
- [x] 7.8 `swiftlint lint --strict`, build + full test suite green; manually verify single-appearance, separation, grouping, cross-midnight labels, and running-timer exclusion
## 8. Editor save-dismiss + empty-categories label (revision)

- [x] 8.1 Dismiss the stacked editor on successful save (clear the sheet item in the detail presenter's `onSaved`); keep Cancel behavior; unit-test or manually verify save → editor closes → sheet shows saved values
- [x] 8.2 Always render the Categories line; show localized "none" (`activityDetail.noCategories`, en + ru + `L10n`) when the activity has no categories; update `LocalizationTests` count
- [x] 8.3 Update previews (`Design/COMPONENTS.md` if the layout description drifts) and run `swiftlint lint --strict`, build + full test suite green; manually verify both behaviors on a simulator
