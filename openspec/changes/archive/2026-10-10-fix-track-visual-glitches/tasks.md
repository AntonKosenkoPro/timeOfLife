## 1. Reproduce + worktree setup

- [x] 1.1 Open the isolated worktree `../timeOfLife.wt/fix-track-visual-glitches` (branch `opsx/fix-track-visual-glitches`) and confirm `openspec status --change fix-track-visual-glitches` resolves there.
- [x] 1.2 Reproduce all three glitches on the current tree and record evidence: (a) start a timer and screenshot the centered locked-name text vs the leading-aligned idle row, (b) screenshot the Categories/Recents header sitting directly on chips with no separator, (c) seed >6 recents and confirm only 6 show with no scroll. Save the evidence with the change.

## 2. Track visual fixes (in the worktree)

- [x] 2.1 Leading-align the running locked name: add the trailing `Spacer()` grammar to `runningNameRow` in `TrackContent.swift` so it matches `lockedNameLabel` (icon + text pushed leading, `lineLimit(1)` + tail truncation kept, no animation/geometry change).
- [x] 2.2 Insert a `Divider` separator between header and chips in both below-action branches (`recentActivities` and `runningTagSelector` in `TrackContent.swift`), using existing `Theme` spacing/tokens only; keep the empty-recents branch as header + separator + hint.
- [x] 2.3 Raise Recents cap to 12: update `TrackViewModel.storeRecents()` to `store.recents(limit: 12)` and `RecentActivitiesChips.recents(from:limit:)` default to `12` together.
- [x] 2.4 Pin the chip-area footprint and add internal scroll: wrap the `RecentActivitiesChips` flow in a vertical `ScrollView` with a fixed height equal to the current 6-chip footprint, so 12-chip overflow scrolls on the chip axis only and the page `AdaptiveVerticalLayout` frame, main-action frame, and below-action slot frame do not grow.

## 3. Tests + verification

- [x] 3.1 Update/extend SwiftTesting coverage: recents cap 12 (VM store limit + `recents(from:)` slice + >12 omits oldest), locked-name leading grammar, separator presence in both branches, overflow scrolls internally without growing the page/slot.
- [x] 3.2 Re-run the identical 1.2 repro in the worktree and record fixed-tree evidence (leading-aligned ticking name, both separators, 12 recents reachable via chip-area scroll with the page stationary).
- [x] 3.3 Run `swiftlint lint --strict`, `xcodebuild` build (warnings-as-errors per `project.yml`), and the Track-related `xcodebuild test` suites green; verify D10 holds (main-action frame identical across idle/ready/running/saving/saved/error) plus an AX-size preview pass.
- [x] 3.4 Re-check `Requirements/FURPS/Timetracking.md` rows for conflicts and confirm no strings/theme-token fallout (no new `L10n` copy, `Theme`-only colors).

## 4. Docs + ready

- [x] 4.1 Update `docs/project-context.md` only if the Track description drifted (cap 6 wording); leave baselines untouched (archive folds them later).
- [x] 4.2 Run `openspec validate --all --strict` green and confirm `openspec status --change fix-track-visual-glitches` shows all artifacts done.
