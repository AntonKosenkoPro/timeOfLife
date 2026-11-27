## Context

See [proposal.md](proposal.md) for the product scope. Lifio has one local timer draft per account file, one `LocalStore` mutation boundary, and a same-account sync relay. Ordinary Stop already saves one entry and clears its draft through that boundary, including from the Live Activity deep link. Recents come from committed entries; the planner must stay separate from both recency and entry provenance.

## Goals / Non-Goals

**Goals:** one source for Today and its progress, one atomic local Stop, offline-first edits that converge, and an additive deploy.

**Non-Goals:** a cross-device timer lock, new Apple APIs, a general-purpose sync protocol for all data types, or any change to History/Insights aggregation.

## Decisions

### 1. A Track destination with its own stable composer

Push Today onto the existing Track navigation stack rather than adding a tab or overloading the Track body. Put the compact progress entry in the navigation chrome, outside the timer's measured layout. Keep it reachable when the list is empty and while a timer runs. Test localized counts, narrow screens, Dynamic Type, and VoiceOver without resizing Start/Stop.

Use one persistent inline field fixed at the bottom of the screen with a single scrollable list above it, rendered as a contrasting card with a taller touch target so it reads apart from the background. Render Recents as a single horizontally scrollable chips line pinned between the composer and the keyboard with a breathing gap above the keyboard, visible only while the keyboard is open; each chip shows its Recent's first category icon and filters by typed prefix, and tapping one fills the composer and stages that Recent's full category set for the created task. After a chip tap the line shows only the selected chip until the user types again; the staged set persists until the draft clears or another chip is tapped. The task list carries no section header. Prepend new tasks at the top with an expanding insertion (opacity-only under Reduce Motion). Row swipes use native swipe actions with icon + label: trailing-side delete, leading-side complete/reopen. Tapping a task opens the task editor sheet — the manual entry form with the Start and End cards omitted (same Name entry behavior, Categories, Notes, order, cards, validation, and save gate); tasks carry an optional ordered category set and optional notes, each synced as its own field intent, and Start copies name, categories, and notes into the draft (Recents fallback for categories only). While linked, draft and task converge live in both directions in the same chokepoint transaction with both screens observing convergence so each refreshes in place without navigation; the locked name never changes. Rows show the task's ordered categories as small icon+name chips under the task name (Live Activity chip grammar), a notes indicator when non-empty, and an accent-colored `In progress` label instead of Start for the running task; no timer-running nav subtitle — the label is the indicator. The progress icon follows done/total: unchecked at 0 (including empty), `checklist` while partial, `checklist.checked` at N/N (N > 0). Linked Stop invalidates the planner snapshot so counts refresh in place. Track preloads the Today projection for its progress control so counts present actual values on first paint from warm local data. Track reloads its snapshot when returning from a planner-initiated Start so the running timer presents at once. Re-asserting focus after the fact still flashed the keyboard, because SwiftUI `onSubmit` offers no API to suppress the Return resign. The composer is therefore a UIKit-backed field (`UIViewRepresentable` around `UITextField`) whose delegate performs the submit and declines the default Return behavior, so the field never leaves first responder; draft-clear, section mount/unmount, and snapshot reload all preserve the same field instance. Use the existing capped newest-first Recents data, matching case-insensitive prefixes and filling exact text only. Keep draft/focus identity independent of row snapshots. Validate using the existing timer name rules; submit through the keyboard Return key or the composer's Add accessibility action — no separate visible Add button. The composer carries a trailing clear button (Track × grammar). The running-timer notice lives as a nav-bar subtitle under the Today title, not an inline caption. When the draft matches no Recent, the chips line shows the localized no-match placeholder. Offer an accessible reorder path (not drag-only), and prefer row-local motion over rebuilding the list. Reuse durable, resource-scoped deletion/undo rather than introducing another confirmation and restore model.

### 2. One ordered backlog; Today is a projection

Store an independent task ID, validated name, order key, and nullable `completed_on` civil date. The writing device captures the local Gregorian civil date at the completion action; the date is synced as a date, not an instant other devices reinterpret. Today's view uses the viewing device's current local date. It filters to open tasks plus completions on that date, preserving the shared order; progress derives from the same snapshot. Recompute when the date/time zone changes and on resume. No day container, scheduled rollover, or per-task date update is needed. Manual completion and reopen only change the task's completion field.

Persist an ordinary entry's text/tags independently. Planner tasks and their edits never become Recents or History rows. An open task starts with the ordinary exact-text category inheritance and the text copied at Start.

### 3. Associate the run, not the entry

Persist the starting task's ID with the single local draft, as part of Start. Gate Start at the mutation boundary so a second Start cannot replace a pending or active run, and recheck the task is still available. Retagging, notes, and backdating preserve the ID. Do not put the ID in an entry or Live Activity payload; drafts do not sync.

Extend the existing Stop transaction: save the entry, enqueue its create, mark the linked unfinished task complete and enqueue that field update if needed, then clear the draft. An already-completed or missing task is a no-op for the planner, not a failure for time capture. A save failure rolls back the planner change as well; duplicate/retry handling uses the existing stop identity and does not rerun completion on a replay. Preserve existing pending-notes review and stale Live Activity link fences. Neither a later notes review nor a manual entry infers or repeats completion from matching names.

### 4. Sync per-task mutations, not an entire day

Add account-scoped planner operations and a planner-only change feed to the existing authenticated relay, behind `backend/api/openapi.yaml`. Use immutable client operation IDs and field-specific intent: a rename does not send rank or completion, and Stop sends completion only. The relay serializes acceptance per account, deduplicates operation IDs even if the response was lost, and assigns commit-ordered revisions to task changes. Latest accepted intent for a field wins; concurrent changes to other fields compose. Keep receipts long enough for offline retries without a time-based expiry in v1. A latest-state row (including a retained deletion marker) and a separate receipt avoid retaining a full snapshot for every mutation.

Use ordered position keys insertable between neighbors so appending or moving a row does not rewrite the full list. Apply a locale-independent total order with task ID as the final tie-breaker; the rank allocator must handle concurrent inserts in the same gap and still let a later move place a row between them. Do not rely on floating-point midpoints or device clocks. Rank encoding and its parity fixtures belong to implementation.

Pull account-scoped pages in revision order, not display order or `updated_at` order. Fix a committed upper watermark per pull; persist each applied page and cursor atomically. A task superseded past the watermark belongs to the next pull. Ordering of revision assignment and commit must not allow a previously invisible lower revision to appear behind an advanced cursor. Reuse session guards, the transactional outbox, and cycle-exit publication. Pending local field intents stay visible until acknowledged or superseded; apply deletions before planner drain. A delete marker is terminal for its task ID, even if a delayed create arrives later; only local undo before a successful push can restore it. Existing `/deletions` and entry/category resurrection stay unchanged so older clients never see a new tombstone type.

## Risks / Trade-offs

- **Same task started on two offline devices** → both actual entries remain valid; a repeated completion replay creates no second effect, and conflicting completion-field mutations converge under the declared relay policy. The feature does not coordinate device timers.
- **Date boundary or travel** → completion date is fixed; today is local to each device, so devices on different dates may temporarily show different completed rows. Unfinished tasks remain visible on both.
- **Extra relay state** → account-scoped revisions, delete markers and receipts trade storage for durable replay and ordering. Index the bounded page query and cascade all planner data on account deletion; do not time-expire markers or receipts in v1.

## Duplication assessment (day-planner §15.3)

`PlannerTask` and `RunningTimerDraft` overlap on exactly three fields
(name/`activity_text`, ordered `categoryIDs`, `notes` — `TimeEntry` owns
the same three). A shared value type with mapping at the boundary was
assessed and rejected, for concrete reasons:

- The Codable shapes are load-bearing contracts: the relay wire format
  (`PlannerTask` ↔ `PlannerTaskWireDTO` ↔ OpenAPI), the transactional
  outbox payloads (`PlannerOperationPayload`, `TimeEntry`), and the
  durable undo snapshots all decode by flat key. Embedding a shared
  struct changes the key nesting unless every container hand-rolls a
  flattened `Codable` — which keeps the duplication while adding a
  mapping layer, not removing it.
- The lifecycles never coincide: the task is synced, identity-bearing
  (`id`, `positionKey`, `completedOn`), and survives Stop; the draft is
  a local-only singleton (`startedAt`, `status`, `plannerTaskID`) that
  Stop clears. No call site can hold "either" — every reader needs the
  wrapper's own fields, so a shared inner type saves no branches.
- `TimeEntry` would have to join for the abstraction to be complete,
  tripling the blast radius (entry writes, entry outbox, History,
  search, Insights) for zero behavior gain.

The models stay separate; convergence lives in the chokepoint methods
(`updateRunningDraftCategories/Notes`, `savePlannerTaskSheet`), which
are the only place the overlap is named. Revisit if a fourth owner of
the triple appears.

## Migration Plan

Use additive PostgreSQL/SQLite migrations, including cascading account ownership, and an additive account-file migration that leaves existing notes, entries, categories and active drafts intact. Existing drafts acquire no planner link. Deploy relay support first. Against a pre-planner or rolled-back relay, an unsupported planner route leaves planner writes queued and ordinary sync usable. Rollback redeploys the prior image without dropping new tables or changing old endpoint shapes; verify account purge still cascades planner data on that image. No on-disk compatibility decoder or import from the closed prototype.

## Research

- Topic (resumable change feed): PostgreSQL `/websites/postgresql/15`, PostgreSQL 15, `Keyset pagination of ordered incremental changes using a strictly increasing revision, explicit ORDER BY, index range and LIMIT` — [index ordering](https://www.postgresql.org/docs/15/indexes-ordering.html) supports bounded indexed revision slices.
- HIG `/websites/developer_apple_design_human-interface-guidelines`, current guidance, `Lists and tables editable reorder controls, text fields Return key, accessible affordances and motion` — [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) and [Focus and selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection) guide the checklist and focus/reorder affordances.
- Apple API `/websites/developer_apple_swiftui`, iOS 18 SDK via Xcode 16+, `iOS 18 SDK via Xcode 16+ SwiftUI FocusState and TextField onSubmit with stable view identity while adding list items` — [onSubmit](https://developer.apple.com/documentation/swiftui/view/onsubmit(of:_:)) connects hardware/software Return; [focus binding](https://developer.apple.com/documentation/swiftui/view/focused(_:)) keeps the field focusable. Keyboard continuity still needs a device check.
- Best practice `/websites/postgresql/15`, PostgreSQL 15, `PostgreSQL 15 explicit row locking per account and transactional change cursors; commit visibility and statement snapshots at Read Committed` — [transaction snapshots](https://www.postgresql.org/docs/15/transaction-iso.html) and [explicit locking](https://www.postgresql.org/docs/15/applevel-consistency.html) constrain revision allocation and watermark visibility.
- HIG Searching/Search fields `/websites/developer_apple_design_human-interface-guidelines`, current guidance, `Search interface suggestions shown while typing and presenting matching results` + `Text fields autocomplete and input assistance without shifting surrounding layout` — [Searching](https://developer.apple.com/design/human-interface-guidelines/searching) prescribes predictive suggestions and [Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields) live refinement; the field stays stationary while writing. Constrains the stationary-field plus above-keyboard chips shape in Decisions §1.
- UIKit `/websites/developer_apple_uikit`, current guidance, `UITextFieldDelegate textFieldShouldReturn return value resign first responder keyboard stays` — [textFieldShouldReturn](https://developer.apple.com/documentation/uikit/uitextfielddelegate/textfieldshouldreturn(_:)) returning false runs custom behavior without the default resign; SwiftUI `onSubmit` exposes no equivalent suppression. Constrains the composer field choice in Decisions §1.
- ActivityKit research not applicable: no new ActivityKit call or payload change; reuse the checked-in app deep link. GRDB/pgx/SQLite use existing transaction and migration seams; no new dependency behavior assumed.

## Research reconfirmation (implementation base, 2026-11-25)

Re-ran the bundle against the implementation base before coding — no revisions to the approach above:
- Topic `/websites/postgresql` — `docs /websites/postgresql/15 "keyset pagination ... strictly increasing revision ..."`: confirmed index-ordered revision slices (`ORDER BY revision ... LIMIT` over an indexed range) remain the documented pattern; feed design (committed upper watermark per pull, `WHERE revision > after AND revision <= watermark`) follows it.
- Topic `/websites/postgresql` — `docs /websites/postgresql/15 "explicit row locking ... SELECT FOR UPDATE ... Read Committed"`: confirmed §13.2.1 (Read Committed: `SELECT FOR UPDATE` waits on concurrent updaters, re-evaluates `WHERE` on the updated row version) and §13.4.2 (explicit blocking locks) — per-account revision allocation uses a `planner_seq` row locked with `SELECT FOR UPDATE`; allocation + task write + receipt commit in one transaction.
- HIG `/websites/developer_apple_design_human-interface-guidelines` — `docs ... "lists and tables editable reorder ..."`: confirmed Lists-and-tables best practices (editable tables, reorder affordance, brief selection feedback) and focus/keyboard guidance — Today uses a reorder-capable list with an accessible non-drag reorder path, not drag-only.
- Apple API `/websites/developer_apple_swiftui` — `docs ... "iOS 18 TextField onSubmit with stable view identity ..."`: confirmed `onSubmit(of:)` fires on hardware/software Return and `focused(_:)` keeps the composer field focusable — inline composer keeps draft/focus identity independent of row snapshots; `submitScope(_:)` contains submission propagation. Keyboard continuity on device stays a manual check (task 4.1).
- Waivers (unchanged): ActivityKit N/A (no new ActivityKit call/payload; Stop reuses the checked-in deep link); GRDB/pgx/SQLite N/A (existing transaction/migration seams, no new dependency behavior assumed).
