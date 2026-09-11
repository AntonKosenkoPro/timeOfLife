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

### 1. Tap on entry → EntryDetail (push, read-first) — SUPERSEDED

- **Superseded by `edit-entry-from-activity-detail`**: no separate
  read-first EntryDetail push exists. Tapping an ActivityDetail entry row
  opens the unified entry form directly as a full-screen cover in EDIT mode
  (`manual`) or LOCKED mode (imported, read-only with delete only).
  History row taps still open the Activity detail sheet (not EntryDetail).
- The original EntryDetail content (activity name + categories, start/end/
  duration, provenance, Edit + Delete) now lives on that unified form.

### 2. EntryEditor (sheet, mutation) — SHIPPED (as unified form, cover)

- **Delivered by `edit-entry-from-activity-detail` as the unified
  `LogTimeView` form** (CREATE / EDIT / LOCKED modes), presented as a
  **full-screen cover** from ActivityDetail rows — not a third stacked
  sheet, and not a separate EntryEditor type.
- EDIT corrects one interval (activity reassignment via Track search +
  quick-create, start/end with Calendar duration preservation, Save gated
  on activity + end > start, LWW `updateEntry` with stale-write error);
  LOCKED exposes imported entries read-only with delete as the only
  mutation. Activity reassignment uses the full Activity picker
  (resolving the §2 open question toward full search, not a simpler list).

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

### 4. Manual entry addition (no-timer start/end) — SHIPPED

- **Delivered by the `add-manual-entry` change**: a Calendar-grammar
  `LogTimeView` + `LogTimeViewModel` (`Features/ManualEntry`) with Activity /
  Starts / Ends rows, inline single-open pickers, an Add validity gate,
  5-min-floor/+1h defaults, and Calendar-style duration preservation.
- Two entry points share the sheet: a "+" on the History toolbar and a
  "Log time" action on the ActivityDetail sheet (pre-filled).
- The Activity row reuses Track's searchable sheet with quick-create via
  the shared `ActivitySearchHosting` protocol (not `EntryEditor` create
  mode — no `EntryEditor` exists yet; when entry editing lands it gets its
  own sheet per §2).
- Persists via the existing `LocalStore.createEntry` (`source:"manual"` +
  transactional outbox); overlaps and future end-times allowed.

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

### 8. Entry delete/undo from History — PARTIALLY SHIPPED (detail cover)

- **Delivered by `edit-entry-from-activity-detail` for the ActivityDetail
  surface**: the unified form's bottom Delete → destructive confirm titled
  "Delete this entry?" (entry-focused, names no activity) → durable undo
  buffer (no outbox row) → dismiss + reload; restore via the default system
  Undo confirmation (shake → Undo prompt → confirm restores exactly the most
  recent entry, restorable until the app restarts, U7 supersession, cold-launch
  commit via the global reconciliation). No UndoToast on this surface.
- Still deferred: History-row swipe-to-delete and the app-wide UndoToast
  rollout (`local-first-sync-architecture` tasks 3.3–3.6); History rows
  stay swipe/long-press-free.

## Sequencing lean (to revisit)

1. History read-only list (step 1 — this change).
2. EntryDetail + EntryEditor (tap-to-open + edit + delete/undo) — SHIPPED as the unified entry form cover (`edit-entry-from-activity-detail`; no separate EntryDetail type).
3. Manual entry addition — SHIPPED (`add-manual-entry`; standalone sheet, both entry points).
4. History filtering.
5. ActivityDetail (if it earns its place) + per-activity timeline.
6. Provenance labels (can land earlier on EntryDetail if desired).

Each step is its own OpenSpec change; do not bundle.