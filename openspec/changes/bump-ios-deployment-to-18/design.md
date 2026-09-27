## Context

See `proposal.md` for motivation. Current state: the app target pins iOS 15.0 in three `project.yml` places while the test host pins 17.0; `AppNavigationStack` carries an iOS 15 `NavigationView` fallback beside the iOS 16 `NavigationStack` path; `TagSelector` and `RecentActivitiesChips` hand-roll greedy flow packing because `Layout` needs iOS 16+; `ShellToolbar` duplicates its scope because inline `if` in `.toolbar` needs iOS 16; `EditorSheetScaffold` guards `presentationDetents`; `Theme.color(_, alpha:)` and `AppConfig` carry pre-16/14 guards. The lock-screen Control is spec'd (`lock-screen-controls` baseline) but has no widget target in `project.yml`. Constraints: `LocalStore` stays the single mutation chokepoint (App Group `group.com.antonkosenko.timeoflifeapp`); XcodeGen-managed project (edit `project.yml`, generate, never hand-edit `.pbxproj`); `Theme` semantic colors only; user strings via `L10n` + both locales; pre-release so no on-disk migration.

## Goals / Non-Goals

**Goals:**
- Single bump (15.0 → 18.0) with all version debt removed in the same change, sequenced mechanical → deletional → Control target so each phase stays reviewable.
- Ship the missing ControlWidget target against the already-spec'd behavior.

**Non-Goals:**
- No `@Observable` migration, no Charts adoption, no new iOS 18 features beyond the spec'd Control, no rewrites of legitimate measurement code (`AdaptiveVerticalLayout`, readout/header measurement) — see proposal Non-goals.

## Decisions

- **Pin 18.0 in all three `project.yml` spots + unify the test host at 18.0, drop `armv7`.**
  Rationale: one floor, one CI matrix; `armv7` is meaningless on arm64-only iOS 18. Alternative (leave test host split) rejected — the split exists only because of the 15 floor.
- **Delete the `NavigationView` fallback; standardize on `NavigationStack`.**
  Removes `popTo`, the recursive `AnyView` destination chain, and converts 8 `NavigationView + .navigationViewStyle(.stack)` roots (shell, Manage Categories, Log Time, editor scaffold, previews). Alternative (keep the polyfill harmlessly) rejected — it is the largest dead-code surface and the user's #4 asks for full cleanup.
- **One shared `Layout`-protocol flow layout replacing both greedy packers.**
  Rationale: `TagSelector` and `RecentActivitiesChips` implement the same algorithm; a single `FlowLayout: Layout` kills ~120 lines of GeometryReader/PreferenceKey/UIFont measurement and fixes Dynamic Type scaling. ctx7: `/websites/developer_apple_swiftui` — "Layout protocol custom flow layout". Alternative (convert each file independently) rejected — duplicates the new component.
- **Unconditional modern APIs: single toolbar scope, `presentationDetents`, native opacity, bare `Logger`.**
  Rationale: each is a 2–10 line collapse once the floor allows it. `Theme.color` callers (4 sites) move to native opacity — verify the old "`Color.opacity` is iOS 16+" comment during implementation; if the claim proves wrong, still delete the helper and keep native calls. Alternative (leave helpers) rejected per #4.
- **Add the ControlWidget target now, tasks sequenced after the cleanup.**
  WidgetKit `ControlWidget` toggle + `alwaysAllowed` AppIntent reading/writing the active per-account file in the shared container; the intent enqueues the outbox row in the same transaction and never syncs directly (baseline D-outbox invariant). ctx7: `/websites/developer_apple_swiftui` — "ControlWidget lock screen control". Pin: iOS 18 SDK via Xcode 16+. Alternative (stack the target as a follow-up change) rejected by the user's 1+2 call — accepted cost: a widget review snag blocks the cleanup from landing, mitigated by phased commits in `tasks.md` order.

## Risks / Trade-offs

- [Risk] Widget target (entitlements, App Group reads pre-first-unlock, Control Center review behavior) entangles new code with pure deletion → Mitigation: tasks ordered mechanical → deletional → widget; landable in stacked PRs if review stalls.
- [Risk] `Theme.color` comment may misstate SDK history → Mitigation: verify callers compile against native opacity during implementation; helper deletes regardless.
- [Risk] Preview-only `NavigationView`s (Insights/History) break silently → Mitigation: build all previews + run the full `xcodebuild test` suite, plus the README real-device smoke including the Control toggle.
- [Risk] Only one baseline spec names the floor, but `app-shell` scenarios imply old toolbar behavior → Mitigation: re-check `app-shell`/`timer-capture-experience` deltas during implementation; add a delta only if a requirement (not implementation) actually changes.

## Migration Plan

Single change, three phases: (1) pins + docs + spec delta; (2) deletions + full test suite green; (3) widget target + device smoke. Rollback: revert the change (pre-release, no user data, no server impact). Post-archive: update `docs/project-context.md` routing + incomplete-list and `openspec/README.md` if the active-change set changed.

## Open Questions

- None that change specs, approach, or task breakdown. The `Theme.color` verification and the `app-shell` scenario re-check are implementation steps, already in `tasks.md`.
