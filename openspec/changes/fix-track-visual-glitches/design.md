## Context

See `proposal.md` for motivation. Current state (`TrackContent.swift`, `RecentActivitiesChips.swift`, `TrackViewModel.swift`):
- `runningNameRow` builds `FieldCard { HStack { timer icon + Text(draft) } .frame(maxWidth: .infinity) }` with no trailing `Spacer`, so the `HStack` content centers; the `saving` sibling `lockedNameLabel` already ends with `Spacer()` and reads leading-aligned. The below-action slot keeps both branches mounted with opacity hiding so the main action never moves (D10).
- `recentActivities` and `runningTagSelector` render a `.caption` header directly above chips (`RecentActivitiesChips` / `TagSelector`) with only `Theme.spacingSmall` gap and no `Divider`.
- Recents cap is 6 in two places: `TrackViewModel.storeRecents()` (`store.recents(limit: 6)`) and `RecentActivitiesChips.recents(from:limit:)` (default `6`). `RecentActivitiesChips.body` is a bare `FlowLayout` that grows vertically with content inside the page-level `AdaptiveVerticalLayout` `ScrollView`, so more chips would grow the page.

Constraints: `Theme` semantic colors only, no raw `Color`; `L10n` strings only (no new copy needed); D10 main-action pinning must hold; `project.yml` warnings-as-errors; SwiftTesting coverage for the touched logic.

## Goals / Non-Goals

**Goals:**
- Leading-align the running locked name with a one-line grammar fix that mirrors `lockedNameLabel`.
- Insert a theme-only `Divider` between header and chips in both below-action branches.
- Raise the cap to 12 behind a fixed-height, internally-scrolling chip area that preserves the current page footprint.

**Non-Goals:**
- No change to recents ordering, exact-text identity, chip tap contract, tag-selector behavior, sync/outbox, navigation, or accessibility contracts beyond keeping them intact.
- No new theme tokens, strings, or dependencies; no backend/OpenAPI work.

## Decisions

- **Leading alignment via trailing `Spacer` in `runningNameRow`** (not `multilineTextAlignment` or frame `alignment:`): the sibling `lockedNameLabel` already proves this grammar — `HStack { icon + Text + Spacer() }` inside `FieldCard` — so the running card adopts the identical shape. Alternative (frame alignment on the `Text`) rejected: it fixes one line but diverges from the established card grammar and risks trunk-vs-wrap differences on long names. The `Text` keeps `lineLimit(1)` + tail truncation.
- **`Divider()` between header and chips in both branches**: one `Divider` after the caption `Text` in `recentActivities` and one in `runningTagSelector`, each padded with existing `Theme` spacing. Alternative (custom `Rectangle` hairline) rejected: `Divider` already renders the system hairline and adapts to light/dark without tokens work. Empty-recents hint branch keeps the header + separator + hint order so geometry stays stable.
- **Fixed-footprint chip area = `ScrollView(.vertical)` + fixed height budget around `RecentActivitiesChips`**: the `ScrollView` wraps the existing `FlowLayout` (no layout rewrite), its height is pinned to the measured 6-chip-era footprint (a constant derived from the current max rows at default type size, verified in previews), and content beyond it scrolls on the chip axis only. Alternatives: (a) letting `FlowLayout` grow — rejected, it pushes the page `ScrollView` and moves the bottom spacer against D10; (b) paging/horizontal scroll — rejected, the spec forbids horizontal scrolling for Recents. The below-action `ZStack` keeps both branches mounted with opacity hiding, so the slot still keeps the taller branch's height and the main action never moves; the scroll view never captures horizontal gestures.
- **Single cap constant (12) threaded through both layers**: `storeRecents(limit: 12)` and `recents(from:limit: 12)` change together (default parameter updated, no new parameter plumbing). Alternative (VM-only or view-only change) rejected: either layer alone silently re-caps to 6.

## Risks / Trade-offs

- [Risk] Fixed chip-area height clips at large Dynamic Type sizes → Mitigation: verify at AX sizes in previews; the internal scroll already absorbs growth, and the page-level `AdaptiveVerticalLayout` still collapses spacers before clipping.
- [Risk] Nested vertical `ScrollView` (chip area inside page scroll) fights gestures → Mitigation: chip area is the only bounded scroll region on the page, height-pinned so the outer scroll only engages when spacers are exhausted; manual swipe check in both states.
- [Risk] 12 chips grow `belowActionSlot`'s taller branch and shift D10 balance → Mitigation: the chip scroll height is pinned to the old footprint, so measured slot height is unchanged; snapshot the main-action frame across states in tests/previews.
