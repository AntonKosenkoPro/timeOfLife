## Context

See proposal.md (Why) for motivation. Current state constraining the approach:

- The only red banner is `OfflineBanner` (`Features/Auth/Views/RootView.swift:210-226`): a `Theme.danger` top strip rendering `L10n.offlineBanner.text`, inserted via `.safeAreaInset(edge: .top)` in the `RootView` signed-in body (`RootView.swift:41-45`) with an ease-in-out animation on `container.connectivity.isConnected`. The earlier "two banners" theory is disproved — there is no legacy banner anywhere else (repo-wide grep for `OfflineBanner` hits only `RootView.swift`; `offline.banner` hits only `String+Localized.swift` + the two strings files).
- Keep-surface 1 (History pull notice, read-only): `HistoryPullModel.refresh()` returns the offline verdict without burning a cycle (`Features/AppShell/ViewModels/HistoryPullModel.swift:56-59` — `guard connectivity.isConnected … showNotice(.offline)`); `HistoryView` renders `PullNoticeBanner()` below the nav bar when `pull.notice != nil` (`Features/AppShell/Views/HistoryView.swift:77-79`), and `PullNoticeBanner` shows `L10n.historyPullOffline.text` with the `HistoryOfflineNotice` identifier (`HistoryView.swift:279-290`). A mid-cycle connectivity loss routes to the error dialog, never back to the notice (`HistoryPullModel.swift:13`).
- Keep-surface 2 (Profile sync status, read-only): an offline-triggered cycle sets `status = .error("offline")` (`Features/Sync/SyncController.swift:233-236`); `ProfileView.syncStatusRow` renders the `.error(message)` case as a `profile.syncError` row with the message subtitle (`Features/AppShell/Views/ProfileView.swift:90-108`).
- `TrackView.swift:12` already documents "no offline hint" on Track — after removal the Track tab shows no offline indication at all (accepted consequence, stated in the PR body).
- `Theme.danger` stays: it is used by `PrimaryButton` (destructive), `TextFieldWithError`, `ListRow`, `ErrorBanner`, and `OtpCodeField` — the banner removal must not touch the semantic color itself.
- Scope guards: do NOT touch `LogTimeView.swift`, `HistoryView.swift` (read-only), `CatalogIcon.swift`, `openapi.yaml`, `TrackContent.swift`, `TrackView.swift`, `Design/TOKENS.md`.

## Goals / Non-Goals

**Goals:**

- No red/global offline banner renders anywhere in the app, online or offline.
- Offline remains discoverable through the two keep-surfaces: the History pull-to-refresh offline notice and the Profile sync-status error row.
- No dead localization: the `offline.banner` key, both strings rows, and the `L10n` case disappear together; `LocalizationTests` stays green.

**Non-Goals:**

- Any change to sync triggers, cycle behavior, connectivity detection, or offline editing (signed-in offline keeps working).
- Any change to the keep-surfaces' copy, styling, or behavior (`history.pull.offline`, `error.offline`, Profile row — all untouched).
- UndoToast, "via \<Source\>" labels, lock-screen ControlWidget, device quota/picker (#46) — unchanged, still deferred per `docs/project-context.md`.
- Any store or backend change (`openapi.yaml` untouched).

## Decisions

### 1. Full removal, not restyle or relocate (over keeping a subtler banner)

The user tested latest `main` and explicitly asked for removal: the pull notice plus sync status is enough indication. Restyling (e.g. a subtler color) would keep a third offline surface with no owner and no spec requirement. Alternatives rejected:

- Keep one subtle banner: contradicts the explicit user decision; duplicates the two keep-surfaces.
- Move the banner into Track only: Track's spec voice is "no offline hint" (`TrackView.swift:12`); adding one there would be a new surface, not a removal.

### 2. Remove the `L10n.offlineBanner` key and both strings rows in the same iteration (over leaving the key orphaned)

Repo rule (S5/U4): user-facing strings live behind `L10n` + both locales. Leaving an unreferenced case would break the "prefer existing utilities; remove dead code" rule and rot the `allCases` count test. `error.offline` (`error.*` ad-hoc keys) is a different key and stays — it feeds `ErrorLocalization` and the auth view-model error paths.

### 3. `LocalizationTests`: count 137 → 136, rename the stale banner wording (over deleting the offline test)

The `allCasesCount` test pins the enum size, so it drops by exactly one. The `offlineMapping` test exercises `ErrorLocalization.message(for: .offline)` → `error.offline`, which is unrelated to the removed banner key — it stays, with its display name reworded from "banner text" to "error text" so no stale reference remains.

## Risks / Trade-offs

- [Risk] A user offline on the Track tab gets no hint until they pull on History or open Profile → Mitigation: accepted consequence per the user decision, stated in the PR body; Track already documents "no offline hint".
- [Risk] Another agent's in-flight change touches `RootView.swift` (shared checkout) → Mitigation: this diff touches only the `OfflineBanner` struct + its `safeAreaInset` block + the L10n/strings/tests rows; verified at the end that the branch diff contains only owned files.
- [Trade-off] No automated UI test asserts banner absence (no view-test infra for `RootView`) → Accepted: removal is compiler-pinned (deleting the struct while a reference remains fails the warning-as-error build; deleting the `L10n` case while strings rows remain is caught by review of the strings files), plus the manual checklist in tasks §4.

## Migration Plan

None — pre-release policy (no on-disk backward compat): no schema change, no migration. Rollback is revert-only. `docs/project-context.md` lines mentioning `OfflineBanner` ("`OfflineBanner` remains/stays") are updated in the same iteration.

## Open Questions

None. Copy uses existing `L10n` strings only — no new localized strings; one key removed, so `LocalizationTests` counts drop by one.
