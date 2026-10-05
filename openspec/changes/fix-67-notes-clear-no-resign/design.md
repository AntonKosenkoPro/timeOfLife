# Design: fix-67-notes-clear-no-resign

## Decisions

1. **Invert the resign (explicit over simultaneous).** The blanket
   simultaneous tap cannot exempt one child — any exemption races it (B1) or
   masks it with a flicker (async refocus). A plain card-level `.onTapGesture`
   fires only for taps no child consumes (labels, padding, background), so the
   × tap physically cannot resign. Controls that must dismiss resign in
   their own handlers, where the intent is visible and deterministic.
2. **No resign on the name row.** The pushed `NamePicker` autofocuses its
   own field, so focus transfers directly and the keyboard never drops —
   resigning first would replay the dismiss/reappear flicker. The link
   carries no gesture at all.
3. **Resign rides existing actions elsewhere.** `TagSelector.onToggle` and the
   shared `toggle(_:)` (all four start/end pills) set `focusedField = nil`
   alongside their state change — one line each, no new types, no flags.
4. **Delete, don't deprecate.** The B1 binding/flag/drag and the async refocus
   are removed entirely (S5 dead-code rule); `FormCard`'s contract comment is
   rewritten around the inverted rule.

## Risks

- **Missed child leaves the keyboard open.** Mitigated by auditing all five
  `FormCard` sites (name link needs none — see decision 2; chips, pills,
  label-taps verified on device/simulator) and by the recorded verify pass:
  × (stays), chip (resigns), pill (resigns), label (resigns).
- **No ctx7 needed:** pure SwiftUI gesture semantics, no external dependency.
