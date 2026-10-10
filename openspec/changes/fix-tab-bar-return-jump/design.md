## Context

See `proposal.md` (Why). Current state in `ios/TimeOfLife/TimeOfLife/Features/AppShell/Views/AppShellView.swift`: one `TabView` with three independent `NavigationStack(path:)` (track / history / insights), each bound to its own `[ShellRoute]` in `AppShellViewModel`. Hiding is per-destination — `.toolbar(.hidden, for: .tabBar)` on Profile (`ProfileView.swift`), Manage Categories (`ManageCategoriesView.swift`), the pushed entry form (`LogTimeView.swift` chrome), and `NamePicker.swift` — per `per-tab-navigation-paths` Decision 3, whose Risks section accepted toolbar interpolation as a non-goal. Roots carry the layout that jumps: Track's `AdaptiveVerticalLayout` derives top/central/bottom spacers from measured viewport height, and History/Insights pin the `CompactTimer` via `.safeAreaInset(edge: .bottom)`. Constraints from `docs/project-context.md`: LocalStore chokepoint (untouched here), Theme-only colors, L10n (no new strings in this change), XcodeGen (`project.yml`, never `.pbxproj`), per-tab path independence, iOS 18+ floor.

## Goals / Non-Goals

**Goals:**
- One visibility owner per stack: each tab root declares bar visibility as a pure function of its own path depth; destinations carry no toolbar modifier.
- Bar + root content settle in one transaction on pop (Back tap and swipe-back commit), with cancel restoring hidden without a flash.
- Per-tab independence preserved: each stack's visibility follows only its own path.

**Non-Goals:**
- No custom tab bar, no UIKit bridge, no new dependency, no Profile-as-sheet conversion, no Track/History/Insights content or sync changes, no string or theme-token changes.

## Decisions

1. **Path-driven `toolbarVisibility` on each stack root; every push past a
   tab root is path-observed.** Each `NavigationStack` root applies
   `path.isEmpty ? .automatic : .hidden` for the tab bar instead of
   destinations owning the hiding. Rationale: visibility flips at pop
   commit (Back tap) rather than after the destination fully disappears,
   collapsing the two-pass restore into the pop transaction; it is
   declarative (no lifecycle timing hacks), per-tab by construction, and
   unit-testable at `AppShellViewModel` level.
   - *Device finding (spike, iPhone 17e iOS 26.4):* a stack-level
     declaration unconditionally wins over destination modifiers, and
     `.automatic` does NOT defer to them — with a plain
     `visible`-at-root ternary, the Track→NamePicker link push (empty
     path) showed the tab bar. Hence the second half of this decision:
     the Track name row's caller-local `NavigationLink` became the
     `ShellRoute.namePicker(initialText:)` value (snapshot rides the
     route; completions resolve at the destination from the owning tab's
     view model), so no push from a tab root escapes path state. The same
     conversion covers the running notes button merged from main mid-change
     (`ShellRoute.notesEditor(initialText:entryName:)` — a second empty-path
     push from the Track root with no destination hiding of its own). The
     remaining caller-local links (Manage Categories from Profile,
     pickers inside the pushed entry form and sheets) always sit under a
     non-empty path or outside any tab bar. Destination backstop
     modifiers are kept where they agree with stack state (never disagree,
     so no conflict is possible).
   - *Alternative (rejected):* `onAppear`/`onDisappear` state flips on parent + destination (StackOverflow `q/79562576`, `q/79497891` accepted answers) — fires earlier during interactive drags, but `onDisappear` also fires on tab switch (needs an `isCurrentTab` guard threaded through every tab) and swipe-cancel leaves the bar wrongly visible. Not needed: the commit-flip covers Back-tap and swipe-commit, and cancel leaves the path (hence the bar) untouched.
   - *Alternative (rejected):* keep per-destination modifiers and only add animation — the modifier's evaluation is owned by the disappearing view, so animation cannot join the pop transaction; the stagger persists (proven by the before-video's second motion burst).

2. **Animate the root height change in the same transaction (the "option 3" half).** Track's `AdaptiveVerticalLayout` spacing derivation and the History/Insights `safeAreaInset` compact-timer slot animate with the bar change (GeometryReader-measured viewport pattern per `q/79497891`'s answer) so freed space is granted simultaneously with bar removal/insertion instead of sequentially. Rationale: Apple's two-phase behavior (bar removed → space granted) is what makes the jump harsh on viewport-sensitive layouts; joining them removes the visible second pass without touching content itself.
   - *Alternative (rejected):* `.animation(.none)` snap on the bar — removes the delay but reads as an abrupt pop-in; kept as a last resort if co-animation proves unstable on any supported device size.

3. **No UIKit bridge, no custom tab bar.** `hidesBottomBarWhenPushed` via SwiftUI-Introspect is the smoothest today (true UIKit push/pop animation), and a custom `safeAreaInset` bar gives full control — both rejected: Introspect adds a third-party dep against the repo's minimal-dep rule (S1), needs per-major-OS opt-in (iPad floating bar on iOS 18, Liquid Glass interpolation on iOS 26), and fights SwiftUI's own toolbar ownership; a custom bar re-owns accessibility, Dynamic Type, safe-area, and the compact-timer daylight contract permanently. Revisit only if the blessed-API spike fails on device across all supported sizes.
   - *Alternative (rejected):* `NavigationStack` outside `TabView` (single global stack) — reported smooth in one thread, but collapses per-tab independence and violates the `app-shell` per-tab-paths contract.
   - *Alternative (rejected):* sheets/covers for Profile instead of pushes — Apple's HIG direction and deletes the problem class, but contradicts the in-force pushed-page spec; a separate product decision, not this bugfix.

## Risks / Trade-offs

- [Risk] Interactive swipe-back commit still restores late (path flips at release, not drag start) → Mitigation: spike records button-tap AND swipe commit/cancel per tab; add the `onAppear`-driven supplement (decision 1 fallback) only for the lagging gesture, guarded by tab identity.
- [Risk] Swipe-cancel flashes the bar (appears on drag, must re-hide) → Mitigation: cancel path asserts hidden + destination unchanged; covered by the new spec scenario and the repro script.
- [Risk] Viewport-measurement feedback loop on Track (spacing change re-measures viewport, oscillates) → Mitigation: reuse the existing hysteresis/no-explicit-animation precedent in History elevation gating; animate the derived spacing value, never the measurement.
- [Risk] Compact-timer inset geometry shifts on History/Insights roots during co-animation → Mitigation: verify timer clears the bar on roots and never floats on pushes at every supported size; inset stays on the root, never moves to destinations (per-tab design's existing mitigation).
- [Risk] iOS-version behavior drift (bar hosting changed in 17.4, floating bar on iPadOS 18, Liquid Glass on 26) → Mitigation: no version branches; verify on the iOS 18+ simulator matrix + one physical device; UIKit-bridge rejection keeps us on the API Apple fixes.

## Migration Plan

Land behind no flag (pre-release, no on-disk format, no API): move the modifiers + add the co-animation in one change on the isolated `opsx/fix-tab-bar-return-jump` worktree; repro recording before, identical repro after. Rollback = revert the change (destinations regain their modifiers, roots lose theirs; no data migration involved).

## Open Questions

- None blocking: whether the swipe-commit case needs the `onAppear` supplement, and the exact animation curve joining bar + content, are spike outcomes recorded in tasks — neither changes the spec scenarios above.
