## Context

See proposal.md (Why) for motivation. Current state constraining the approach:

- `LogTimeView` (`Features/ManualEntry/Views/LogTimeView.swift`) renders one `NavigationStack` wrapping a `ScrollView` with cards in this order: `nameCard → categoriesCard → notesCard → startsEndsCard` (one combined card holding both `timeRow`s). Each `timeRow` expands an inline picker below the pills: `.graphical` month grid for dates, `.wheel` hour/minute/period for times — both wrapped in `GeometryReader` with fixed heights, single-open via `expandedPicker`, inside the outer `ScrollView`.
- `HistoryView` (tab root inside the History `NavigationStack` provided by `AppShellView.navigationRoot`) opens the unified form two ways: CREATE via `.sheet(isPresented:)` (Log Time from `[+]`), EDIT/LOCKED via `.fullScreenCover(item: $editingEntry)` whose content is `LogTimeView` — which embeds its **own** `NavigationStack`. So the pushed EDIT form is a modal cover containing a single-root inner stack.
- Two reported bugs: (#51) the wheel `UIPickerView` captures vertical drags, so pull-down-to-scroll starting on the picker never reaches the outer `ScrollView`; (#50) the leading-edge back swipe does nothing — a `fullScreenCover` has no navigation back stack to pop (the inner `NavigationStack` holds only its root), so there is no back gesture to recognize.
- Agreed rule (proposal): native gestures are always correct — never disable a system gesture to accommodate layout; change the presentation instead of patching the gesture.
- Scope guards for clean successor rebases: NO duration display (`feat-entry-duration-subtitle` owns the toolbar principal item), NO name-field clear/autocomplete (`feat-name-field-affordances` owns `nameCard` internals), and NO touches to `CatalogIcon.swift`, `openapi.yaml`, `RootView.swift` OfflineBanner, or `TrackContent.swift`.

## Goals / Non-Goals

**Goals:**

- Exact card order Activity name → Start → End → Categories → Notes in all three modes, so Start/End sit directly under the name and scrolling with an open picker is rarely needed.
- Every native gesture works: pull-down-to-scroll (picker open or closed), swipe-down-to-dismiss (sheet), edge-back (pushed form), tap-away/scroll-away keyboard dismissal.
- One presentation-line change class with the smallest spec delta that gives the EDIT/LOCKED form a real back stack.

**Non-Goals:**

- Duration subtitle in the nav bar (successor `feat-entry-duration-subtitle`).
- Name-field clear button / autocomplete (successor `feat-name-field-affordances`).
- UndoToast, "via <Source>" labels beyond today's rows, lock-screen ControlWidget, device quota/picker (#46) — unchanged, still deferred per `docs/project-context.md`.
- Any store, sync, outbox, or backend change (`LogTimeViewModel` behavior untouched; OpenAPI untouched).

## Decisions

### 1. Reorder cards exactly: Name → Start → End → Categories → Notes (over picker-style changes)

The issue text prescribes the order; it also fixes the ergonomics half of #51: with Start/End directly under Name, the pickers are visible without scrolling, so the open-picker-plus-scroll collision becomes the rare case instead of the default. Picker styles stay as specced (graphical date, wheel time, single-open, device locale/calendar) — changing them would trade one spec violation for another. `startsEndsCard` splits into `startCard`/`endCard` (one `timeRow` each); `categoriesCard`/`notesCard` move down untouched; accessibility identifiers (`EntryNameRow`, `LogTimeStartDatePill`, …) are preserved so existing UI hooks keep working.

### 2. EDIT/LOCKED presentation: navigation push via `.navigationDestination(item:)` (over keeping `fullScreenCover`)

`HistoryView` already lives inside a `NavigationStack` (`AppShellView.navigationRoot`), so a push gives the form a real back stack for free: the system back button plus the leading-edge interactive pop — the exact gesture #50 reports missing. Alternatives rejected:

- Keep `fullScreenCover`: has no back stack by construction (modal, not pushed); the inner `NavigationStack` holds only its root, so no pop gesture can ever recognize. Patching the gesture (custom drag → dismiss) would violate the agreed rule.
- Sheet instead of cover: keeps swipe-down-to-dismiss but still has no back stack — #50 stays broken.
- Custom edge-swipe-to-dismiss inside the cover: a gesture patch over a presentation problem, explicitly ruled out by the decision.

CREATE keeps its sheet (spec-pinned, swipe-down-to-dismiss already native). The cover's `onDismiss` reload (`invalidate`/`loadIfNeeded`) moves to the push destination's `onDisappear` — same reload path, same lists. `LogTimeView` gains an `embeddedInNavigationStack` flag so the pushed instance skips its internal `NavigationStack` (no nested stacks); the sheet instance keeps it. One Boolean, all chrome (title/toolbar/alert/`task`) shared through a single `formChrome` modifier so CREATE and EDIT can never visually diverge.

### 3. Wheel-in-`ScrollView` collision: order + separate cards + grab area (over disabling gestures)

`UIPickerView` (wheel) legitimately consumes vertical drags that start on its wheels — that is the system gesture working as designed. The fix is layout, not gesture surgery:

- Reorder (Decision 1) puts pickers near the top — rarely any need to scroll while one is open.
- Splitting Start/End into separate cards shrinks each picker's capture area and leaves non-picker grab surfaces (labels, pills row, dividers, card padding, neighboring cards) immediately adjacent, so a scroll drag starting outside the wheels reaches the outer `ScrollView`.
- No `highPriorityGesture`, no `simultaneousGesture`, no scroll-disabling anywhere — the rule forbids them.

This matches the Calendar grammar the form is styled on: compact inline pickers with ample non-picker chrome around them.

### 4. Keyboard dismissal: `@FocusState` + interactive scroll dismissal (over tap-coordinator hacks)

Today the `TextField`s hold no focus state, so neither tap-away nor scroll-away can resign them. Add a `Field` focus enum (name/notes), bind both fields, apply `.scrollDismissesKeyboard(.interactively)` to the `ScrollView` (scroll-away = native behavior), and resign on background taps (`focusedField = nil` on the non-control content area — buttons/pills keep precedence, so picks still work). `.submitLabel(.done)` already resigns via Return. No new toolbar, no coordinator, no change to the validity gate.

## Risks / Trade-offs

- [Risk] Push changes the EDIT visual frame (nav bar back button appears; tab bar behavior follows the stack, not a modal) → Mitigation: intended — it is what makes #50's gesture exist; CREATE sheet is untouched; manual checklist covers light/dark, EN/RU, Dynamic Type.
- [Risk] `navigationDestination(item:)` requires the History `NavigationStack` ancestor → Mitigation: guaranteed by `AppShellView.navigationRoot` in production; previews already wrap `HistoryView` in `NavigationStack`.
- [Risk] Wheel picker still consumes drags starting exactly on its wheels → Mitigation: accepted as correct system behavior (same as Calendar); the spec pins the scenario to drags starting outside the picker; adjacent grab area is one short drag away.
- [Risk] Successor changes (`feat-entry-duration-subtitle` toolbar principal, `feat-name-field-affordances` name internals) touch the same file → Mitigation: this diff keeps `nameCard` internals and the toolbar's principal item untouched and preserves identifiers, so they rebase onto the reordered cards cleanly.
- [Trade-off] No programmatic UI test can perform the leading-edge pop or the wheel-vs-scroll disambiguation → Accepted: gestures get the manual on-device checklist (tasks §4), noted in the PR body; automated tests cover card order + VM invariants only.

## Migration Plan

None — pre-release policy (no on-disk backward compat): no schema change, no migration. Rollback is revert-only. FURPS `Timetracking.md` F13 comment (which names the full-screen cover) is updated to the push in the same iteration.

## Open Questions

None. Copy uses existing `L10n` strings only — no new localized strings, so `LocalizationTests` counts are unchanged.
