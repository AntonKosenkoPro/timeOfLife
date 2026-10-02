## Context

See `proposal.md` — Why (navbar `+` on the populated Manage Categories list animates weirdly on sheet open; empty-state Add via the same `vm.addCategory()` does not). Current state and constraints needed for the approach:

- Presenting surface: `ManageCategoriesView.swift:68-76` toolbar plus (`ManageCategoriesAddButton`) on a populated `List` vs `:44-51` empty-state Add → same `vm.addCategory()` → editor sheet (`CategoryEditorView`: NavigationStack + ScrollView, EditorToolbar, `.task` FocusDelay settle 400ms in `PresentationMetrics.swift:8-19`). The list page itself has no autofocus.
- Suspected cause is presenter-side toolbar / List / NavigationStack-in-sheet churn, NOT the editor keyboard (keyboard is the null hypothesis the probes must rule out).
- Invariants from `docs/project-context.md` (preserved): LocalStore stays the single mutation chokepoint (untouched — no persistence work here); Theme semantic colors only; XcodeGen-managed (`project.yml`, never hand-edit `.pbxproj`); iOS strings EN+RU + `L10n` (no copy changes expected); no OpenAPI change; incomplete surfaces (UndoToast/shake-to-undo, lock-screen widget) not claimed done.
- No external library/framework/SDK/API behavior is load-bearing here (pure SwiftUI presentation) — no ctx7 fetch required.

## Goals / Non-Goals

- Goals: reproduce the glitch deterministically on demand; prove whether the keyboard/autofocus participates; land the smallest presenter-side animation calm that removes the weird plus motion with zero behavior delta.
- Non-Goals (design-level): no change to sheet content, detents, collapse/header, autofocus contract, `vm.addCategory()` semantics, or empty-state/edit paths; no Liquid-glass header rework (#35 context only); probe edits to FocusDelay/autofocus are throwaway and never ship.

## Decisions

- **Repro spike first with slow animations + screen recording (toolbar-plus vs empty-state Add).** Rationale: the two paths share the call-site, so a side-by-side capture isolates the presenter as the variable; slow animations make the churn frame-visible. Alternative (jump straight to animation-nil patch) rejected — risks masking the cause without proof.
- **Keyboard-vs-transition isolation via temporary FocusDelay probes (vary delay / disable autofocus), reverted after.** Rationale: cheapest way to falsify the keyboard hypothesis without redesigning autofocus; `editor-sheet-ux` autofocus-after-settle contract stays intact. Alternative (Instruments trace first) rejected — heavier than a two-value probe for a binary question.
- **Ship only a minimal presenter-side calm (e.g. explicit transaction / animation-nil scoped to the presenting button).** Rationale: keeps the diff reviewable and behavior-identical; scoped to the toolbar-plus path so empty-state/edit rows are unaffected. Alternative (sheet-side transition rewrite) rejected — larger blast radius for a presenter symptom.

## Risks / Trade-offs

- [Risk] Probe edits to FocusDelay accidentally ship → Mitigation: probes are separate uncommitted edits, reverted before the fix commit; tasks gate on a clean `git diff` showing only the presenter hunk.
- [Risk] Animation-nil scoping too broad (kills legitimate transitions) → Mitigation: scope to the presenting button/transaction only; verify edit-row open, empty-state Add, and save/dismiss transitions still animate normally.
- [Risk] Simulator-only repro (device timing differs) → Mitigation: confirm on a physical device at default animation speed before accepting; slow-motion is for diagnosis, default speed is the acceptance gate.

## Migration Plan

- No migration, no rollout flags, no rollback beyond reverting one presenter hunk. Ship as a normal app change; no persistence, sync, or API surface moves.

## Open Questions

- None — the spike answers the only unknown (keyboard vs presenter), and tasks record the outcome before the fix lands.
