# Design: fix-51-picker-width

## Root cause (proven, not hypothesized)

Three independent evidence lines converge:

1. **Live layout frames (pre-fix build on iPhone 17 Pro sim):** with all
   pickers collapsed, the Starts pills sit at x 0.265–0.735 and Ends at
   0.266–0.734, while Name spans 0.080–0.921, Categories starts at 0.080,
   and Notes spans 0.080–0.921. The Start/End cards hug content and center;
   every other card stretches. Screenshots
   (`/tmp/fix51-before-collapsed.png`, `/tmp/fix51-before-edit.png`) match
   the issue-comment screenshot.
2. **Expanded state is fine:** expanding the start date picker stretches the
   card full width (calendar grid 0.080–0.915) because the `GeometryReader`
   around each picker is horizontally greedy. Only the collapsed state —
   where the picker `VStack` is empty — hugs.
3. **Diff archaeology:** pre-#54, the combined `startsEndsCard` held two
   `timeRow`s joined by a `Divider()` (commit `5553a0c` diff). `Divider` is
   horizontally greedy, so it forced the old card full width. Splitting
   into separate `startCard`/`endCard` removed the only width-forcing
   element; the outer form `VStack` is center-aligned, so hugging children
   also center. The `FormCard` extraction (`cb79f45`) kept byte-identical
   chrome (padding → background → clipShape, never a width constraint), so
   the bug lives at the call site, not in `FormCard.swift`.

## Fix

One modifier on `timeRow`'s root `VStack` (the single shared container for
both `startCard` and `endCard`):

```swift
.frame(maxWidth: .infinity, alignment: .leading)
```

- `maxWidth: .infinity` takes the full width the outer form `VStack`
  offers (viewport minus card margins) → collapsed cards stretch
  margin-to-margin like the other editors.
- `alignment: .leading` keeps pills/title leading-aligned (unchanged visual
  order inside the card).
- Expanded pickers are unaffected: the `GeometryReader` already takes all
  offered width; the parent offering full width only stabilizes it (no more
  collapsed↔expanded width jump).
- No gesture impact: no gesture modifier is added, moved, or removed; the
  #50 all-native-gestures rule still holds.
- Alternatives rejected: adding the modifier inside `FormCard` (would
  change all five cards' contract for a one-card bug — wider blast radius
  for parallel agents); restoring a hidden `Divider`/spacer hack (a
  transparent width-forcing view is obscure — the explicit frame states
  intent).

## Verification plan

- Pre-fix screenshots (CREATE collapsed, EDIT collapsed, CREATE date-picker
  expanded): already captured — the red evidence.
- Post-fix: rebuild, reinstall, re-capture the same three states on the
  same sim + EDIT mode; pill/card frames must start at x 0.080.
- Corners: wheel time picker (start + end), graphical date picker
  (start + end), Dynamic Type AX size relaunch, CREATE + EDIT modes.
- S5: `swiftlint lint --strict` clean, warning-as-error build green, full
  iOS suite green (serialized per `docs/ios-test-loop.md`). Backend
  untouched — no `go` run.

## Tests

No new unit tests — deliberately. The fix is a single SwiftUI layout
modifier with no logic (no constant, no computed frame, no branch); there
is no view-test infra in the repo, and any test asserting "the modifier
exists" cannot fail independently of the code it pins (a fake test). The
red/green evidence is the simulator screenshots + accessibility frames
before/after, recorded in the PR body.
