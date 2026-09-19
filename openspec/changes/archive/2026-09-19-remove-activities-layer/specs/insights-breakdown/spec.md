## MODIFIED Requirements

### Requirement: Category and activity lenses with full-credit attribution
The breakdown SHALL offer a lens toggle (`By category | By activity`, default `By category`). The activity lens SHALL group committed entries by trimmed exact text (`Gym` and `GYM` are distinct rows) and attribute each entry's full duration to its text row (rows sum to the hero). The category lens SHALL attribute each committed entry's full duration to **every** category stored on that entry; category rows MAY therefore sum above the hero, which is correct behavior, not an error. Entries with no categories SHALL aggregate into a localized "Without category" row that sorts by its own total like any other row. No edit on one entry SHALL reclassify any other entry.

#### Scenario: Category lens default
- **WHEN** the user opens Insights
- **THEN** the category lens is selected, showing one row per category with committed time in the period plus the "Without category" row when applicable, ordered biggest-first

#### Scenario: Multi-category entry counts fully toward each
- **WHEN** an entry carries two categories
- **THEN** the entry's full duration contributes to both category rows in the selected period

#### Scenario: Activity lens sums to hero
- **WHEN** the user selects the activity lens
- **THEN** rows show one row per exact text with committed time, and the row durations sum to the hero total

#### Scenario: Recategorization reclassifies history
- **WHEN** the user changes one entry's categories and reopens Insights (retags are per-entry; no other entry reclassifies)
- **THEN** only that entry contributes to the updated category set; same-text entries are unchanged
