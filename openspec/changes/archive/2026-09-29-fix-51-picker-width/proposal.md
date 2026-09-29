## Why

Reopened #51 regression: after PR #54 split the combined Starts/Ends card into
separate Start/End cards, the collapsed Start/End cards render narrow —
hugging their date/time pills and centering in the form — while Name,
Categories, and Notes stretch full width (see the issue-comment screenshot).
The pickers must stretch to screen width like the other editors on the page.

## What Changes

- Force the Start/End card content (`timeRow`) to full card width in every
  state (pickers collapsed and expanded), so the collapsed cards stretch
  margin-to-margin exactly like Name/Categories/Notes.
- Call-site fix only: one width modifier on `timeRow`'s root `VStack`
  (covers both `startCard` and `endCard`). `FormCard.swift` is proven
  innocent (identical chrome before/after extraction — no width constraint
  removed there) and stays untouched.
- Non-goals: picker behavior (single-open, wheel/graphical styles, heights),
  gesture handling (#50's area), name/notes internals (#42's area),
  toolbar/nav, `CatalogIcon.swift`, `openapi.yaml`, `RootView.swift`,
  `TrackContent.swift`.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `entry-editor`: Start/End cards keep full card width with pickers collapsed
  or expanded, in all three modes.

## Impact

- `ios/TimeOfLife/TimeOfLife/Features/ManualEntry/Views/LogTimeView.swift`
  (`timeRow` root `VStack` only — minimal diff for parallel agents).
- Simulator screenshot evidence before/after (CREATE + EDIT); no new deps,
  no ctx7 fetch needed (repo-internal SwiftUI layout).
