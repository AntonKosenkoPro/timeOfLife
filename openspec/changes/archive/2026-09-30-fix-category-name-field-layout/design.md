## Context

See `proposal.md` (Why) for motivation. Current state: `TextFieldWithError` (`Core/Design/Components`) wraps its `TextField` in an `HStack(spacing: 0)` with a conditionally-shown 44pt `ClearTextButton`, inside `.padding()` (16 all sides). The inner `TextField` has no height floor, so the row renders ~54pt without × and ~76pt with it. Both `CategoryEditorView` and `EmailEntryView` attach `.focused` to the `TextFieldWithError` wrapper `VStack`, two levels above the focusable view; `LogTimeView` (notes row) and `NamePicker` bind `.focused` to the `TextField` directly and pin it to `minHeight: 44`. `CategoryEditorView` autofocuses instantly in `onAppear` while the medium-detent sheet + large title are still animating; `NamePicker` delays autofocus ~400ms in a cancellable task for the same keyboard-mid-transition hazard. Floor is iOS 18+ (no availability guards); Apple SwiftUI docs are unversioned latest (ctx7 `/websites/developer_apple_swiftui`, queries: "`focused(_:)` modifier placement", "conditionally showing views vs overlay/hidden layout semantics").

## Goals / Non-Goals

**Goals:**
- One shared-component fix that heals every `TextFieldWithError` call site without per-site layout forks.
- Autofocus that lands the field fully in viewport on real devices, in both create and edit modes.

**Non-Goals:**
- No unifying of the three field patterns (`TextFieldWithError` / `NamePicker` fieldCard / `FormCard` rows) — future work.
- No detent, keyboard-avoidance, or scaffold redesign; the D13/D21 contract (`INTERACTIONS.md`) stays as-is.

## Decisions

1. **Thread `FocusState<Bool>.Binding` into `TextFieldWithError`; apply `.focused` to the inner `TextField`.**
   Apple docs: programmatic set moves focus to *the modified view*, and every example binds the field directly — nothing documents container-to-child forwarding. Alternative (inline the field in `CategoryEditorView` like the LogTime notes row) rejected: it would fork the U2 single-error layout the component exists to share. Callers pass `$isNameFocused`/`$isEmailFocused` down; the wrapper-level `.focused` modifiers are removed.

2. **Stabilize height with `.frame(minHeight: Theme.minTapArea)` on the inner `TextField`, plus horizontal-only card padding.**
   The 44pt × then fits inside an already-44pt row however visibility toggles — same precedent as LogTime notes row and `NamePicker` fieldCard, so all three patterns converge on one rule. Stabilizing alone would freeze the card at the tall ~76pt value (44pt row + full 16pt padding), so the card padding drops to horizontal-only (NamePicker parity, ~44pt card). Alternatives: `.overlay(alignment: .trailing)` for × (zero layout impact per docs, but restyles padding/tap geometry and diverges from the two healthy call sites) and a `.hidden()` placeholder (reserves a dead 52pt slot permanently). Rejected both. `.fixedSize()` explicitly avoided (docs warn it can push past parent bounds).

3. **Delay category-editor autofocus past sheet settle via cancellable task (~400ms, `NamePicker` precedent).**
   Keeps the `INTERACTIONS.md` "focused on appear" contract perceptually while letting the detent/title animation and keyboard transition complete before ScrollView auto-scroll computes. Alternative (explicit `ScrollViewReader` scroll-to-field) rejected: it fights the system's own keyboard auto-scroll and adds scroll-offset bookkeeping the scaffold deliberately avoids. Dismiss-before-fire cancels the task (spec scenario).

4. **`EmailEntryView`: spike first, touch only if broken.**
   Same wrapper-`.focused` smell but no × (no layout symptom) on the production-verified auth path. The change wires it to the new binding parameter only if the spike confirms autofocus is dead there; otherwise it stays untouched to avoid auth-flow regression risk.

## Risks / Trade-offs

- [Risk] Wrapper-level `.focused` may actually forward on the running iOS version, making the focus move a no-op behaviorally → Mitigation: still correct per docs (forwarding is undocumented); verified by the "programmatic focus reaches the field" spec scenario on-device.
- [Risk] The ~400ms settle constant may mistime on slow devices or future OS animation curves → Mitigation: verify on iPhone SE simulator (worst case: short screen + full keyboard); constant lives next to `NamePicker`'s so both tune together later.
- [Risk] Previews/screenshots can't catch keyboard-timing clipping → Mitigation: spec scenarios are validated by a manual simulator pass (add + edit, SE + standard, EN + RU, default + larger Dynamic Type), recorded in the tasks.
- [Trade-off] `TextFieldWithError` gains a focus-binding parameter (minor API churn on a 2-call-site component) in exchange for documented-correct focus everywhere it is used.

## Migration Plan

No migration: no on-disk format, API, sync, or localization changes. Rollback is a plain revert of the change. Archive folds the two delta specs into `category-management` and `editor-sheet-ux` baselines per the standard flow.
