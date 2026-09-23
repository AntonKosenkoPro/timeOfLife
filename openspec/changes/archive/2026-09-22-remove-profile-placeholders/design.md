## Context

See proposal.md (Why) for motivation. Current state (`Features/AppShell/Views/ProfileView.swift`): a `NavigationView` + `List` with four sections — Account (working sync controls), Library (working Categories), Connections (two static `ListRow`s: Integrations, Export), App (two static `ListRow`s: Appearance, Data & Privacy + working Erase). The four static rows have no `Button`/`NavigationLink`/action, so they render as inert text. Constraints: `Theme` semantic colors only; strings via `L10n` + both locales (U4); `LocalStore` untouched (this change is view + strings only); pre-release policy allows deleting `Codable`/string shapes in place with no legacy branches (D-pre-release in project-context.md).

## Goals / Non-Goals

**Goals:**
- Every visible Profile row is live (tappable or a status); no inert rows.
- The short screen still looks intentional: 2 sections with a local-first footer.

**Non-Goals:**
- No behavior change to sync, auth sheet, Categories destination, or erase semantics (confirm alert + `eraseAll` + logout + path reset stay as-is).
- No new rows (e.g. version/build) and no "Soon" badges — each removed destination returns via its own future change.
- No Design-system component changes; `ListRow` reused as-is.

## Decisions

- **Merged `On This Device` section over HIG-strict separate destructive (A1 over A2).** Alternative was Library (Categories) + headerless destructive section. Merged wins: 2 balanced sections instead of 3 with two singletons; the red `Theme.danger` styling + existing destructive confirm alert already separates Erase. Keeps the diff to one section struct instead of two.
- **Delete the 7 unused `L10n` keys outright; add one `profileOnDevice` header.** Alternative was leaving dead keys for future reuse. Rejected per pre-release no-compat policy and S5 dead-code rule — re-adding a key later is one line per locale.
- **Footer carries the local-first explanation** ("time lives on this device; erase removes…", exact copy at implement time, en+ru). Alternative was no footer. Footer chosen to fill the signed-out 3-row void and to state what Erase does before the confirm alert.
- **Account section untouched**, including the `container` vs `sync`/`session` environment-object split and the `EnableSyncPresenter` restore-then-sheet wiring (see the `ProfileView` header comment — nested `container.syncController` reads never invalidate, so the separate objects stay).

## Risks / Trade-offs

- [Risk] Destructive row adjacent to Categories invites mis-taps → Mitigation: keep `Theme.danger`, existing confirm alert, and footer warning; no reorder (Erase stays last).
- [Risk] Signed-out screen is only 3 rows and may feel empty → Mitigation: footer text fills vertical rhythm; accepted as honest for a utility sheet.
- [Risk] `LocalizationTests` parity failure from key add/remove → Mitigation: tasks require updating both `.strings` files + `L10n` + running the suite.
- [Risk] Future Export/Appearance changes re-add sections → Mitigation: spec delta explicitly names them as non-required until their own changes; no migration needed.
