## Context

See `proposal.md` Why for motivation. Current state: `ProfileView.onDeviceSection` wraps the erase `ListRow` in an outer `.foregroundStyle(Theme.danger)`, but `ListRow` sets explicit inner styles — icon `Theme.accentPrimary`, title `Theme.textPrimary` (`ListRow.swift:25,32`) — so the danger never lands and the row reads as a regular navigation row. The confirmation alert (`role: .destructive` + permanent-delete message) is already correct and stays untouched. Constraints: `Theme.*` tokens only, iOS 15+, no new strings (both locales already have `profile.eraseLocalData*` keys), SwiftLint + warnings-as-errors clean.

## Goals / Non-Goals

**Goals:**
- Make the row's destructive nature visible at first glance (danger icon + title) and semantic (`role: .destructive`) with the smallest possible diff.
- Keep the fix robust against the swallow: danger styling lives inside the label, not on an outer wrapper.

**Non-Goals:**
- No layout/copy/flow change: same section, order, footer, title, alert, wipe semantics, auth-reset behavior.
- No shared-component redesign: `ListRow` defaults for regular rows stay exactly as-is.
- No new tokens, strings, dependencies, or data-plane work.

## Decisions

- **D1 — Danger styling moves inside the label (not the outer wrapper).** The outer-modifier approach is what silently broke; inner explicit styles win in SwiftUI, so the fix must set danger where `ListRow` actually paints (icon + title) or route a tint through it. Alternatives considered: leaving the outer modifier and hoping the `List` environment propagates it (rejected — that is the current bug), vs. abandoning `ListRow` for a bespoke card like entry/category delete (rejected — breaks Profile's list rhythm for a minimal fix).
- **D2 — Prefer a local label-level override; add a `ListRow` tint/destructive path only if the reviewer wants reuse.** Default: keep the diff to `ProfileView` so no other `ListRow` caller changes rendering. Alternative (reusable `tint`/`destructive` param on `ListRow`) fixes the bug class for future destructive rows but widens the blast radius to every caller; acceptable if preferred, but not required for this change.
- **D3 — Give the control `Button(role: .destructive)`.** Matches the alert's Erase button, the sign-out row, and the entry/category delete buttons; carries VoiceOver/system destructive semantics for free instead of relying on color alone. No custom accessibility traits beyond what the role provides.

## Risks / Trade-offs

- [Risk] Future edit re-applies an outer-only style that `ListRow` swallows again → Mitigation: keep danger inside the label and verify visually (light + dark); the delta-spec scenario pins the row's destructive presentation.
- [Risk] `Theme.danger` contrast weak in one appearance → Mitigation: single screenshot check in light and dark; no new color math.
- [Risk] Longer RU title (`"Стереть локальные данные"`) wraps or truncates differently once styled → Mitigation: verify RU layout in the same pass; no copy change means no new truncation class.
- Trade-off accepted: color + role signal scanning, not accident-prevention — the row remains one tap from the (correct) confirmation alert. Counts / isolation / friction stay explicitly out of scope.

## Migration Plan

None — purely presentational, no state, schema, or API change. Rollback is reverting the row styling.

## Open Questions

None. Visual verification (light/dark, EN/RU) is a task, not an open design question.
