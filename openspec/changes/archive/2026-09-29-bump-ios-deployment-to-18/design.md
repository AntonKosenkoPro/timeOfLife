## Context

See `proposal.md` for motivation. Current state: the app target pins iOS 15.0 in three `project.yml` places while the test host pins 17.0; `AppNavigationStack` carries an iOS 15 `NavigationView` fallback beside the iOS 16 `NavigationStack` path; `TagSelector` and `RecentActivitiesChips` hand-roll greedy flow packing because `Layout` needs iOS 16+; `ShellToolbar` duplicates its scope because inline `if` in `.toolbar` needs iOS 16; `EditorSheetScaffold` guards `presentationDetents`; `Theme.color(_, alpha:)` and `AppConfig` carry pre-16/14 guards; 14 one-parameter `onChange(of:)` call sites use the pre-17 form. The lock-screen Control stays spec'd-but-deferred (`lock-screen-controls` baseline) but has no widget target in `project.yml`. Constraints: `LocalStore` stays the single mutation chokepoint (App Group `group.com.antonkosenko.timeoflifeapp`); XcodeGen-managed project (edit `project.yml`, generate, never hand-edit `.pbxproj` — and never hand-edit generated `Info.plist` files, which XcodeGen rewrites from `info.properties`); `Theme` semantic colors only; user strings via `L10n` + both locales; pre-release so no on-disk migration.

## Goals / Non-Goals

**Goals:**
- Single bump (15.0 → 18.0) with all version debt removed in the same change, sequenced mechanical → deletional so each phase stays reviewable.

**Non-Goals:**
- No ControlWidget target (deferred — judged excessive for now). No `@Observable` migration, no Charts adoption, no new iOS 18 features, no rewrites of legitimate measurement code (`AdaptiveVerticalLayout`, readout/header measurement) — see proposal Non-goals.

## Decisions

- **Pin 18.0 in all three `project.yml` spots + unify the test host at 18.0, drop `armv7`.**
  Rationale: one floor, one CI matrix; `armv7` is meaningless on arm64-only iOS 18. Alternative (leave test host split) rejected — the split exists only because of the 15 floor.
- **Delete the `NavigationView` fallback; standardize on `NavigationStack`.**
  Removes `popTo`, the recursive `AnyView` destination chain, and converts 8 `NavigationView + .navigationViewStyle(.stack)` roots (shell, Manage Categories, Log Time, editor scaffold, previews). Alternative (keep the polyfill harmlessly) rejected — it is the largest dead-code surface and the user's #4 asks for full cleanup.
- **One shared `Layout`-protocol flow layout replacing both greedy packers.**
  Rationale: `TagSelector` and `RecentActivitiesChips` implement the same algorithm; a single `FlowLayout: Layout` kills ~120 lines of GeometryReader/PreferenceKey/UIFont measurement and fixes Dynamic Type scaling. ctx7: `/websites/developer_apple_swiftui` — "Layout protocol custom flow layout". Alternative (convert each file independently) rejected — duplicates the new component.
- **Unconditional modern APIs: single toolbar scope, `presentationDetents`, native opacity, bare `Logger`, modern `onChange`.**
  Rationale: each is a small collapse once the floor allows it. `Theme.color` callers (4 sites) move to native opacity; the 14 one-parameter `onChange(of:)` sites move to the iOS 17+ two/zero-parameter form (mandatory — the old form errors under warnings-as-errors on the new floor). Alternative (leave helpers) rejected per the full-cleanup scope.
- **No ControlWidget target.**
  Rationale: judged excessive for now — the change stays a pure floor bump plus deletion, and the `lock-screen-controls` baseline remains the future contract. Alternative (ship the target in this change) was implemented then removed at the user's call.

## Risks / Trade-offs

- [Risk] Only one baseline spec names the floor, but `app-shell` scenarios imply old toolbar behavior → Mitigation: re-check `app-shell`/`timer-capture-experience` deltas during implementation; add a delta only if a requirement (not implementation) actually changes (done — none changed).

## Migration Plan

Single change, two phases: (1) pins + docs + spec delta; (2) deletions + full test suite green. Rollback: revert the change (pre-release, no user data, no server impact). Post-archive: update `docs/project-context.md` routing + incomplete-list and `openspec/README.md` if the active-change set changed.

## Open Questions

- None.
