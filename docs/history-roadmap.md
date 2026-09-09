# History Screen — Roadmap

Captures the deferred decisions and future steps for the History experience,
extracted from an explore-mode session. Step 1 (read-only entry list grouped
by day) is tracked separately as its own OpenSpec change; this file holds
everything after it, to be discussed and sequenced into later changes.

The architectural lean from exploration:

- **History is a list of entries (timed intervals), not activities.** An
  activity is a definition; an entry is an event. "What did I spend time on
  and when?" is answered by entries. Activities belong to
  Manage-Activities (definition management); entries belong to History
  (retrospective review).
- **Entries are first-class objects.** They deserve their own detail/editor
  surfaces, distinct from the activity editor. Reusing `ActivityEditor` for
  an entry would conflate two mutation chokepoints (`refineActivity` vs
  `updateEntry`) and two different objects (definition vs event).
- **Each surface has one job.** History = global chronology.
  ActivityDetail (if built) = "everything about one activity".
  EntryDetail = "one interval". Editor sheets stay focused mutation surfaces.

## Target shape (reference)

```
        ManageActivities                 History
              |                            |
              v tap row                    v tap entry row
        ActivityDetail                EntryDetail
         |       |                     |       |
         |       +-[Edit]-> ActivityEditor    +-[Edit]-> EntryEditor
         |              (def sheet)              (event sheet)
         |
         +- entries list (tap -> EntryDetail, same screen as from History)
```

`EntryDetail` is the single shared destination for "one entry" regardless of
where it was opened from (History row or ActivityDetail entries list).

## Deferred items

### 1. Tap on entry → EntryDetail (push, read-first)

- A History row tap pushes `EntryDetail`, not a sheet. Separates "looking"
  from "changing" — most History taps are review, not correction.
- EntryDetail shows: activity name + categories, start/end/duration, source
  provenance ("via Garmin"), an "Edit" affordance, and a "Delete" action.
- Mirrors the Manage-Activities pattern: list row -> detail -> editor sheet.
- Open question: does EntryDetail also show activity notes, or only
  entry-specific data? (Probably entry-specific; activity notes live on
  ActivityDetail.)

### 2. EntryEditor (sheet, mutation)

- Edits one interval: start, end, duration (auto-computed if both set),
  and activity reassignment (change `activity_id`).
- Distinct from `ActivityEditor` (which edits the definition: name/notes/
  categories). Two objects, two mutation paths, two sheets.
- Open question: full Activity picker (like Track's search) vs. a simpler
  pick-from-existing list for reassignment? Reassignment is error-prone;
  worth a deliberate control.

### 3. ActivityDetail (new, read-first) — SHIPPED (superseded)

- **Superseded by the `activity-detail-sheet` change** — but note the shipped
  design inverts this item's original lean: the detail IS reached from
  History rows (tap an entry → activity detail sheet at medium→large
  detents), not from Manage-Activities. It shows the identity header with
  the all-time total, the complete day-grouped entry list, and "Edit
  Activity" stacking the existing editor. It is read-only (no delete; the
  `delete-activity` change will add the destructive surface with
  `ScopeConfirmation`-style confirmation). The remaining open piece below is
  the entry-count scope choice at delete time.
  "delete only this entry" then finds its home on `EntryDetail` instead.

### 4. Manual entry addition (no-timer start/end)

- A create path with no timer: pick activity, set start/end, save.
- Candidate homes: a "+" on the History toolbar, a "Log time" on
  ActivityDetail, or both.
- Reuses `EntryEditor` in create mode (mirrors `ActivityEditor`'s
  create/edit modes).
- Open question: where is the entry point? History "+" is the most
  discoverable for "log something I forgot"; ActivityDetail "Log time" is
  more contextual.

### 5. History filtering

- Filters by Activity, Date range, and Source (provenance).
- Affects History VM query shape — may need store-level filter support
  beyond the current `entries()` (which returns all, newest-first).
- Day grouping must coexist with filters (filter narrows the set, grouping
  buckets the result).
- Open question: filter bar UI pattern (chips vs. a filter sheet). The
  existing `TagSelector` chip pattern is a candidate for Activity/Source
  multi-select.

### 6. "via <Source>" provenance labels (U1) — SHIPPED

- **Delivered by the `activity-detail-sheet` change**: non-`manual` entries
  show a localized "via <Source>" label appended to entry-row captions in
  both the History list and the activity detail sheet (`EntryProvenance`).
  The spec ambiguity was resolved toward rows everywhere; no entry-detail
  surface exists.

### 7. Running / in-progress session in History

- A running timer has a `timer_state` row but no `entries` row until stop
  (`createEntry` fires on stop). So History shows only committed sessions.
- Open question: should a running session appear at the top of History as
  read-only "in progress"? Currently it's only visible via the compact timer.
  Probably defer — the compact timer already covers cross-tab awareness.

### 8. Entry delete/undo from History

- `LocalStore.deleteEntry` + the durable undo buffer already exist for
  entries. The app-wide Undo UI for entries is deferred (per
  `local-first-sync-architecture` tasks 3.3-3.6).
- When built, History rows get swipe-to-delete -> `UndoToast` (30s) +
  durable restore, mirroring Manage-Activities. `EntryDetail`'s delete
  action feeds the same flow.
- The `ScopeConfirmation` "delete only this entry" language already
  anticipates entries as first-class objects.

## Sequencing lean (to revisit)

1. History read-only list (step 1 — this change).
2. EntryDetail + EntryEditor (tap-to-open + edit + delete/undo).
3. Manual entry addition.
4. History filtering.
5. ActivityDetail (if it earns its place) + per-activity timeline.
6. Provenance labels (can land earlier on EntryDetail if desired).

Each step is its own OpenSpec change; do not bundle.