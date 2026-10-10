## Context

`EntryRow` (`Core/Design/Components/EntryRow.swift`) is the read-only History row in the Variant H grid: line 1 is entry text (left, flexible) + duration (right), line 2 is category/provenance caption (left) + timeframe (right), with a leading category-icon column the day headers align to. Entry notes already exist on `TimeEntry.notes` (persisted, synced, editable in the entry form) but no History surface renders them — see proposal.md Why. `HistoryViewModel` resolves every row input (`icon`, `categoryNames`, `timeframeText`, `durationText`, `viaText`); the row stays presentational. `Theme.accentPrimary` is the existing semantic blue — no new color is introduced.

## Goals / Non-Goals

**Goals:**

- A glanceable notes indicator on History rows with non-empty notes.
- Zero disturbance to the Variant H grid and day-header column alignment.
- Presentational-only: no interaction, navigation, sync, or storage change; accessible via the existing row label.

**Non-Goals:**

- No notes excerpt/preview in the row; no separate tap target on the icon.
- No filtering, sorting, or Insights change (explicit proposal non-goals).

## Decisions

### Placement: line 2, immediately left of the timeframe

The icon sits on line 2's trailing edge, immediately before the timeframe text (`[categories, via …] [note.text icon] [14:00 – 15:20]`), in `Theme.accentPrimary` at caption size, baseline-aligned with the timeframe. The duration stays alone and flush at line 1's trailing edge; the icon lives in the metadata line where the eye already scans for entry details. (An earlier iteration placed it on line 1 next to the duration; on-device review moved it to line 2 for a quieter timing column.)

Alternatives considered and rejected:

- **Inline after the entry text** (before the spacer): rejected — long names truncate or push the duration, and the icon would jump horizontally per row instead of sitting in a stable column.
- **Leading edge of line 2's caption**: rejected — the caption is empty for uncategorized `manual` entries, leaving the icon floating.
- **A separate trailing column (chevron-style)**: rejected — it widens the row grid and breaks the day-header trailing-edge alignment (D10) for one glyph.

### Symbol and style

`note.text` SF Symbol, `Theme.accentPrimary`, caption size. No new asset, no raw `Color`, no new `Theme` token. The `Image` itself is excluded from the accessibility tree; presence is folded into the row label (below).

### Plumbing: `hasNotes` input + pure VM helper

`EntryRow` gains `hasNotes: Bool = false` (default keeps every existing call site and preview compiling with today's rendering). `HistoryViewModel` gains a pure `hasNotes(for:)` helper — `!entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` — mirroring the existing `icon(for:)` / `categoryNames(for:)` pattern, and `HistoryView` passes it through. The trim rule lives in exactly one tested place; the row only branches on the Bool.

### Accessibility wording

The existing `accessibilityLabel(entryText:categoryNames:timeframeText:durationText:isInProgress:viaText:)` builder appends one localized "has notes" segment when `hasNotes` is true. One new `L10n` key (`historyHasNotes`), added to both `en.lproj` and `ru.lproj` plus the `LocalizationTests` `allCases` list per U4.

## Risks / Trade-offs

- [Narrow-width crowding: icon + timeframe could squeeze line 2] → Mitigation: caption-size glyph with the existing `Spacer(minLength:)` floor; verify on the smallest simulator in the smoke pass.
- [Two definitions of "empty" drifting (row vs. editor)] → Mitigation: single `hasNotes(for:)` helper with unit tests for empty, whitespace-only, and newline-only notes.
- [Icon-top tuning precedent (`iconTopAdjustment`) suggests fragility] → Mitigation: the notes glyph aligns to the duration baseline rather than the name cap-height, so it does not participate in that tuning; a font-stack change still gets a visual check via the row previews.

## Migration Plan

None needed. Pure UI addition behind a default-`false` input; entries with empty notes render pixel-identical to today. Rollback is a revert with no data consequences.

## Open Questions

None — the placement question that motivated this change is decided above.
