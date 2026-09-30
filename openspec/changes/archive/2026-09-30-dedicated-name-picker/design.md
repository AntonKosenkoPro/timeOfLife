## Context

See proposal.md (Why) for motivation. Current state: `TrackContent.nameField` renders `nameSuggestionsCard` as a `.overlay(alignment: .topLeading)` with `zIndex(1)` — zero layout footprint, so up to 6×44pt rows paint over the Start button 24pt below (issue #69). `LogTimeView.nameSuggestions` renders an inline `VStack` inside the scrolling form — no overlap, but a second implementation of the same prefix filter (`TrackViewModel.nameSuggestions()` vs `LogTimeViewModel.nameSuggestions()`) over two distinct `RecentEntry` shapes (`.text` vs `.activityText`, first-category-icon vs text-only). Track sits in a `NavigationStack` (`AppShellView.navigationRoot`); LogTime CREATE owns a `NavigationStack` inside its sheet and EDIT is pushed on the History stack — so a push-based picker nests cleanly in all three callers with no new presentation machinery. The `entry-editor` gestures requirement protects the edge-back gesture; the design keeps it intact.

## Goals / Non-Goals

**Goals:**
- One shared picker view over a caller-agnostic suggestion value; both VMs keep their pure filters unchanged.
- Push presentation reusing each caller's existing stack; standard back = cancel restoring the pre-push draft.
- Track idle field and LogTime Name row become thin push affordances; overlay + inline lists deleted.

**Non-Goals:**
- No filter-rule changes beyond the test-driven corrections below (prefix, case identity, newest-first preserved; exact match now included, source uncapped).
- No row metadata beyond text + first-category icon; no keyboard-avoidance rework.

## Decisions

- **Shared `Suggestion` value + generic `NamePicker` view over per-VM mapping.** Both `RecentEntry` types map to `{ text, categoryIDs, firstCategoryID? }` at the call site; `onComplete(text, categoryIDs)` routes to `TrackViewModel.select(_)` (+ `syncReadyFromDraft` path) and `LogTimeViewModel.applySuggestion` respectively. Alternative (VM-owned picker logic) rejected: duplicates the purity the VMs already have and blocks previews with static data.
- **Push, not sheet.** All three call sites already own a navigation stack; push gives edge-back, titles (`< Track` / `< Log Time` / `< Edit entry`), and Dynamic Type scrolling for free. A sheet would need its own stack + dismiss grammar and duplicate `LogTimeView`'s existing patterns. Alternative (fullscreen cover) rejected: heavier dismissal contract for identical content.
- **Standard back kept visible; no ✓ button.** Back = cancel/restore is the HIG search contract (field focused → exit restoring prior state) and the only design with zero dead ends: empty field, zero matches, and accidental entry all exit via Back, while Done-with-empty stays a no-op. Hiding the chevron was considered for minimalism and rejected: it saves one system affordance while breaking discoverability, the HIG navigation-bars rule, and the `entry-editor` gestures requirement.
- **Done completes with typed text incl. new names; empty is a no-op.** Non-empty Done prepares the typed text with exact-match-or-caller categories (Track: via the existing exact-match-or-empty sync; entry form: name set, categories kept). Empty-Done-apply was tried and reverted: applying empty has no consumer (Track would idle, the form gate would disable), so it stays a no-op and Back remains the exit.
- **Resign-before-pop on completion (test finding).** Both completion paths resign focus before applying + popping so the keyboard dismissal runs concurrently with the pop transition; resigning implicitly during the pop dismisses the keyboard after Track is revealed and its relayout jumps.
- **Empty input lists all names.** Makes the page browsable without typing and matches the search-field convention; the empty-store state shows the existing recents-empty hint copy.
- **Uncapped source + exact match included (test findings).** The picker reads `LocalStore.allActivityNames()` (same shape/order as `recents(limit:)`, no LIMIT) instead of the chip-capped recents — suggestions cover everything ever used. The inherited exact-match exclusion was dropped: on a dedicated page the exclusion produced a misleading "new name" hint for text that already exists; including the match narrows typing to its row, which doubles as the fastest confirm path. The VMs' old exclusion filters were deleted with their tests (behavior now lives in `NamePickerFilter`, covered there).
- **Pinned field via top-aligned infinite frame (test finding).** A root `VStack` centers itself when its content is short, so the field rode up and down as results switched between rows and hints. The picker root now frames `maxHeight: .infinity, alignment: .top`, keeps one persistent `ScrollView` across all states (rows render in a `LazyVStack` since the source is uncapped), and holds uniform top spacing — state switches change inner content only.

## Risks / Trade-offs

- [Risk] Three-deep push (History → EDIT → picker) buries context → Mitigation: back titles name each level (`< Edit entry`); picker applies draft-only changes so intermediate pops lose nothing committed.
- [Risk] Live-typing into the shared VM re-renders the covered caller → Mitigation: picker edits a local `@State` draft, applying to the VM only on completion/cancel-restore; callers see exactly one update.
- [Risk] Autofocus keyboard jank on push → Mitigation: autofocus waits out the push transition (~0.4s, task-cancelled on pop) — focusing instantly fires the keyboard mid-push and the relayout makes the covered Track screen jump; no custom keyboard-observation code.
- [Risk] Extra tap vs today's type-in-place → Mitigation: Recents chips stay one-tap on Track; picker autofocuses so arrival = type-ready. Accepted cost for killing the overlap class.
- [Trade-off] Two deleted implementations (overlay + inline list) leave dead identifiers (`TimerNameSuggestions`, `EntryNameSuggestions`) → tests/previews updated in the same change; identifiers re-homed on the picker rows.

## Migration Plan

Pure pre-release UI change: no data migration, no API change, no rollout steps. Delete overlay + inline list in the same change that adds the picker (no intermediate state). Rollback = revert the change; baselines untouched until archive.

## Open Questions

- Cursor placement on open with pre-existing text (select-all vs end) — default to end (current append behavior); adjustable in implementation without spec change.
- Whether zero-match hint names the typed text verbatim or generic copy — copy-level, resolved with EN/RU strings at implementation.
