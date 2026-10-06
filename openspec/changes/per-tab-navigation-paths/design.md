## Context

See `proposal.md` (Why). Current state (`ios/TimeOfLife/TimeOfLife/Features/AppShell/Views/AppShellView.swift`): `TabView` with three `NavigationStack`s built by one `navigationRoot` helper, all observing a single `@State isShowingProfile` bool via `.navigationDestination(isPresented:)`. History's entry form uses `.navigationDestination(item:)` on the same stack; Track/History NamePicker pushes use bare `NavigationLink`s; the CREATE Log Time form carries its own inner `NavigationStack` when sheet-presented. Auth keeps a separate path-owned stack (`AppNavigationStack` + `AppRoute`, auth-only). No destination hides the tab bar today. `docs/project-context.md` invariants apply (LocalStore chokepoint, Theme-only colors, L10n, XcodeGen).

## Goals / Non-Goals

**Goals:**
- One independent, inspectable push state per tab; Profile open on tab A is invisible to tabs B/C.
- Tab bar hidden on every push past root; Back is the single exit.
- Preserve `profile-as-page` contracts: system Back (no Done), Categories push from Profile, editor stays a sheet, once-on-exit Track reload.

**Non-Goals:**
- No global single-path merge; tab states stay independent (deep-link/restore deferred).
- No Profile content, sync, auth, or string changes; no push-animation (Liquid Glass morph) work.

## Decisions

1. **Typed shell route + per-tab paths, owned by the shell VM.** Introduce a `ShellRoute` enum (e.g. `profile`, `entryForm(entryID)`, `namePicker(context)`) and hold one path per tab (`trackPath`, `historyPath`, `insightsPath: [ShellRoute]`) alongside `selectedTab` in `AppShellViewModel`. Each tab becomes `NavigationStack(path:)` + `.navigationDestination(for: ShellRoute.self)`. Replaces both the shared `isShowingProfile` bool and the ad-hoc `editingEntry` item + bare `NavigationLink`s where they express the same pushes.
   - *Alternative (rejected):* per-tab bools (`isShowingProfileOnTrack`, …) — fixes the phantom push but leaves N flags, no ordering for Profile→Categories→editor chains, and no place for entry-form/NamePicker to join.
   - *Alternative (rejected):* single global path over the `TabView` — couples tab states, breaks "switch tabs preserves each stack", complicates the compact-timer inset scope.

2. **Fold existing pushes into the path; keep sheets as sheets.** History entry EDIT/LOCKED (currently `navigationDestination(item: $editingEntry)`), Track NamePicker and LogTime-name `NavigationLink`s become `ShellRoute` values pushed on the owning tab's path. CREATE Log Time sheet and CategoryEditor sheet stay sheets (their inner `NavigationStack` + `embeddedInNavigationStack` split in `LogTimeView` collapses once the pushed form is path-driven: pushed form renders chrome-only, sheet form keeps its stack).
   - *Alternative (rejected):* leave `editingEntry`/`NavigationLink`s in place and path-drive only Profile — preserves two navigation mechanisms on one stack (bool/item/link/path), the exact "parallel stacks" confusion being removed.

3. **Hide the tab bar on the destination, not the stack.** Apply `.toolbar(.hidden, for: .tabBar)` on each pushed destination view (Profile, ManageCategories, pushed entry form, NamePicker) rather than toggling TabView selection or hiding at the root. Root keeps the bar; every push hides; pop restores automatically. Covers the Profile→Categories second depth and entry→NamePicker third depth, which per-view hiding otherwise misses.
   - *Alternative (rejected):* hiding via selection/version tricks at the shell level — fights `TabView` lifecycle and breaks the "return restores tab state" scenario.

4. **Per-tab exit reload, not global `onChange`.** Move the Profile-exit `trackVM.load()` from the global `isShowingProfile` flip to a per-tab path transition (pop-to-root on the tab that hosted Profile). Pushes to Categories don't touch the Profile-route exit, so no spurious reloads — same semantics as the `profile-as-page` bool flip, scoped correctly.

5. **Auth stack untouched.** `container.navigation` / `AppRoute` remain auth-only; shell paths live in `AppShellViewModel`, cleared implicitly with the shell on sign-out (existing `beginSignOut` teardown unchanged). No shared `NavigationPath` type between auth and shell.

## Risks / Trade-offs

- [Risk] `NavigationStack(path:)` + value destinations change push identity (bool/item/link → value) — existing UI-test identifiers and back-swipe expectations shift → Mitigation: keep all accessibility ids, add path-level UI test (open Profile per tab, switch tabs, Back) before removing old modifiers.
- [Risk] Hiding the tab bar alters compact-timer inset geometry on History/Insights roots → Mitigation: inset stays on the root (not the push); verify timer still clears the bar on roots and vanishes (not floats) on pushes.
- [Risk] Exit-reload misfires if modelled as "any path change" instead of "Profile route popped" → Mitigation: trigger only on the Profile-route exit transition per tab, not on Categories/editor traffic.
- [Risk] iOS 26 toolbar interpolation (accepted non-goal) persists on Profile→Categories → Mitigation: none in this change; documented, same as `profile-as-page`.

## Migration Plan

- Land behind no flag (pre-release, no on-disk format): replace flag/link/item destinations with path destinations in one change; old `isShowingProfile`/`editingEntry` state removed, not deprecated. Rollback = revert the change (no data migration involved).

## Open Questions

- None blocking: entry-form `TimeEntry` value vs. id in `ShellRoute` (snapshots vs. store re-read on push) is an implementation detail tasks cover without changing the spec.
