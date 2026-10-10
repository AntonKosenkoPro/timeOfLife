## Context

See proposal.md (Why / What Changes) and the delta specs (`specs/category-management/spec.md`, `specs/timer-capture-experience/spec.md`) for motivation and behavior. Current state shaping this design:

- `TagSelector` (`ios/.../Core/Design/Components/TagSelector.swift`) receives `selected: Set<String>` — order is discarded at the view boundary — and swaps the category icon for a `checkmark` inside a fixed `symbolSlotSize` so `FlowLayout` rows never re-pack (COMPONENTS.md D9).
- Order already exists upstream and toggle semantics are settled: `LogTimeViewModel.toggleCategory` and `TrackViewModel.toggleDraftCategory` append-on-select / remove-on-deselect over `[String]`; persistence, sync, and outbox already carry the ordered set. This change touches rendering only.
- `TrackContent.bottomFlow` applies `.transaction { $0.animation = nil }` over the whole below-button slot (keeps the Start/Stop swap instant) — this also covers the running `TagSelector` and will swallow naive view animations.
- Constraining invariants (`docs/project-context.md`, `Design/COMPONENTS.md`, `Design/SCREENS/TimeTracking.md`): Theme semantic colors only; strings in EN + RU via `L10n`; D10 pixel-stability (selection never moves the main action); 44 pt tap targets; no backend/OpenAPI impact.

## Goals / Non-Goals

**Goals:**
- Make tap order visible on both `TagSelector` instances with zero layout disturbance and a fade on every ordinal transition.
- Keep one shared component — Track and entry forms cannot diverge.

**Non-Goals:**
- No toggle/persistence/sync semantic change; no reorder gesture; no Recents-chip change; no new dependencies or API contract change.

## Decisions

### 1. Order-aware input replaces `Set<String>` (single source of truth)
Change `TagSelector.selected: Set<String>` to an ordered `[String]` (selection order = array order). Membership renders via lookup, ordinal via `firstIndex + 1`; both call sites pass their arrays directly (`vm.categoryIDs`, running draft `categoryIDs`) and delete the `Set(...)` wrappers.
- *Alternative considered*: pass `Set` + separate `order: [String]`. Rejected — two parallel sources that can disagree; catalogs are small so linear lookup cost is irrelevant.
- *Pre-release note*: **BREAKING** view API is acceptable (no on-disk compat rule covers view inputs; no legacy branch).

### 2. Ordinal glyph lives in the existing fixed symbol slot
The leading slot keeps `symbolSlotSize` geometry in all three states (icon / checkmark / ordinal). The ordinal is a `Text` in the slot, centered, accent-on-fill colors identical to today's checkmark; single-digit uses the checkmark's semibold size, two-digit ordinals shrink (scaled-down font / `minimumScaleFactor`) to fit the same slot; selection beyond 99 is impossible by cap (catalogs never approach it, cap is defensive).
- *Alternative considered*: let chips grow with content. Rejected — violates D9/D10 (row re-pack moves the main action on Track).
- *Spike to confirm during implementation*: largest Dynamic Type size + two-digit ordinal still fits the slot without clipping.

### 3. Fade via opacity content transition scoped past the nil-transaction
Ordinal `Text` uses `contentTransition(.opacity)` (ctx7: `/websites/developer_apple_swiftui`, query "opacity transition and contentTransition for animating text changes" — `.opacity` fades transparent↔opaque on content change, iOS 16+, takes effect inside an animation block) driven by an explicit animation tied to the ordinal value, applied at the chip-label level so it overrides the ancestor `.transaction { $0.animation = nil }` on Track's `bottomFlow`. The checkmark↔ordinal swap (1↔2 transition) fades the same way since it is the same slot content changing.
- *Alternative considered*: global `withAnimation` in toggle handlers. Rejected — implicit-animation scope is exactly what `bottomFlow` suppresses; per-label explicit animation is surgical and leaves the Start/Stop instant-swap intact.
- *Alternative considered*: `.numericText()` interpolation. Rejected — digit-roll is busier than the requested fade and behaves poorly on insert/remove of the checkmark state.

### 4. Accessibility carries the ordinal
`accessibilityValue` gains a positional form ("selected, 2 of 3") via new `L10n` keys in both locales; single selection keeps the existing selected/not-selected values. The glyph itself stays `.accessibilityHidden(true)` decoration, consistent with today's icon/checkmark treatment.

## Risks / Trade-offs

- [Risk] Track's nil-transaction suppresses the fade in the running selector while LogTimeView animates → Mitigation: verify the fade on both screens during implementation; the per-label explicit animation/transaction override is the mechanism, tested on Track first.
- [Risk] Two-digit ordinal clips at large Dynamic Type inside the fixed slot → Mitigation: shrink-to-fit + spike at AX sizes; slot width is derived from the same `UIFontMetrics`-scaled base so it grows with type.
- [Risk] Renumbering N chips fires N simultaneous fades (visual noise) → Mitigation: accepted — fades are short, simultaneous, and in place; no layout movement accompanies them.
- [Risk] Snapshot/UI tests asserting checkmark presence break → Mitigation: update affected assertions to the ordinal contract as part of implementation tasks.

## Migration Plan

No migration: pre-release, no on-disk format change, no API change. Rollback is revert-only. Docs sync (`Design/COMPONENTS.md` TagSelector block) ships in the same change.

## Open Questions

None — tap-order semantics, 99-cap with shrink-to-fit two-digit handling, both-selectors scope, and fade style were all settled with the requester before proposing.
