## Context

See `proposal.md` for motivation and `specs/editor-sheet-ux/spec.md` for the observable contract.

Both editors today share an identical skeleton: `NavigationView` → `ScrollView` with a custom `Text(title).font(.title.bold())` as the first content element, `.navigationBarTitleDisplayMode(.inline)` with no `navigationTitle`, a `.cancellationAction` Cancel, and a `measuredBottomBar` Save bar pinned via `.safeAreaInset(edge: .bottom)` (D13/D21, `Core/Utilities/BottomBarMeasurement.swift`). The title is therefore scroll content, so on scroll it slides under a bar that holds only Cancel — no header, no boundary (the iOS 16+ scroll-edge bar appearance is transparent).

Constraints that shape the approach: iOS 15 min target (`project.yml`), XcodeGen-managed, `Theme` semantic colors only, accessibility identifiers referenced by tests (`*EditorCancelButton`, `*EditorNameField`, `*EditorSaveButton` must keep their names), L10n keys for titles already exist in both locales, and the user explicitly wants the native SDK mechanism — no custom elements.

## Goals / Non-Goals

**Goals:**
- One native, system-owned collapsing header shared by every editor sheet.
- A single reusable scaffold so future editor sheets (quick-create activity, F7) inherit the pattern with zero header code.
- Zero new localization keys; zero changes to save/cancel/validation semantics.

**Non-Goals:**
- No UIKit appearance overrides, no scroll-offset `PreferenceKey` plumbing for the header, no custom bar overlays.
- No change to the searchable Activity search sheet, Manage Categories, or pushed screens.
- No workaround for pre-15.4 large-title bugs (see Risks — untestable and effectively extinct on devices).

## Decisions

### D1 — Native large title, explicit `.large` display mode
**Choice:** Move each editor's title to `navigationTitle(...)` with `.navigationBarTitleDisplayMode(.large)`, and delete the custom title text from the scroll content. Cancel stays a `.cancellationAction` toolbar item.

**Rationale:** This is the entire Apple collapsing-header mechanism — collapse animation, inline-title transition, bar material, and scroll-edge transparency are all system-owned. Explicit `.large` (not `.automatic`) matters because inside a sheet `.automatic` resolves to `.inline` on iOS 15, which would silently reproduce today's broken state.

**Alternatives considered:** A custom `PreferenceKey`-tracked overlay bar replicating the collapse — rejected: custom elements, reimplements UIKit behavior, and diverges across OS versions. `safeAreaInset(edge: .top)` header — rejected: content would scroll under a permanently pinned bar, not a collapsing one.

### D2 — Accept native typography drift
**Choice:** The at-rest title becomes the native large title (34pt regular) instead of the current 28pt bold custom text.

**Rationale:** Bold style cannot be applied to the native large title. The user accepted the typography change in exchange for fully native behavior; Apple's own editor sheets (Contacts, Calendar) use the same 34pt regular. "Nothing changes on open" holds structurally — Cancel still floats top-left, the big title still sits in the same position.

### D3 — `EditorSheetScaffold` in `Core/Design/Components/`
**Choice:** A generic scaffold owning the presentation shell, with both editors becoming thin instantiations.

```swift
struct EditorSheetScaffold<Content: View, BottomBar: View>: View {
    init(
        title: String,
        cancelTitle: String,
        isLoading: Bool,
        cancelAccessibilityId: String,
        usesMediumDetent: Bool,
        onCancel: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder bottomBar: @escaping () -> BottomBar
    )
}
```

Internally it owns: `NavigationView(.stack)` + `ScrollView` with the standard padding/maxWidth/reserve (`Theme.screenHorizontalPadding`, `Theme.maxContentWidth`, measured bottom-bar reserve), `.navigationBarTitleDisplayMode(.large)`, `navigationTitle`, the Cancel `.cancellationAction` button (disabled while loading), `measuredBottomBar`, `interactiveDismissDisabled(isLoading)`, and the iOS 16 `presentationDetents([.medium, .large])` availability branch gated by `usesMediumDetent`. What stays per-editor (outside the scaffold): `@FocusState`, `onAppear` focus, dismiss-on-save observation, and the field content. `@ViewBuilder` closures capture the caller's property wrappers, so `@FocusState` in each editor keeps working exactly as it does with `.sheet` content today.

**Rationale:** The user explicitly wants future editor sheets to share this UI; a component is a stronger guarantee than a documented pattern. Placing it in `Core/Design/Components/` follows the existing component-library convention (that's where `PrimaryButton`, `ErrorBanner`, `TextFieldWithError` live, with contracts in `Design/COMPONENTS.md`).

**Alternatives considered:** A `.modifier` instead of a container — rejected: a modifier cannot own the `NavigationView`/`ScrollView` structure cleanly. Per-screen duplication with a Design-doc pattern — rejected: drifts, and this change exists precisely because a shared presentation was wanted.

### D4 — iOS 15 collapse behavior verified by spike; residual risk accepted
**Choice:** Trust the spike result from the iOS 15.5 simulator (the only installable 15.x runtime): at-rest large title, collapse into the bar on scroll, re-expansion at the top edge, and Cancel behavior all verified. Accept untested 15.0–15.4.

**Rationale:** The known early-15 large-title-in-sheet bugs were fixed well before 15.5, and real-world iOS 15 devices run 15.7+/15.8+ (which behave like 15.5). Chasing 15.0–15.4 workarounds would reintroduce the custom elements this change exists to remove.

### D5 — Accessibility and identifiers unchanged
**Choice:** Keep every existing accessibility identifier; the title becomes the navigation bar's native header element (an `AXHeading` in the bar), which is the correct semantics and strictly better than a static text inside content.

**Rationale:** Tests and UI-automation hooks reference `CategoryEditorCancelButton` / `ActivityEditorCancelButton` and field identifiers; renaming them would break the automation contract for no gain.

## Risks / Trade-offs

- **Medium-detent + large title interplay** (iOS 16+): in `.medium` the 34pt title occupies a large share of the half-sheet. In practice both editors focus the name field on appear, which expands the sheet. [Risk: medium looks cramped with the keyboard dismissed] → Mitigation: same tradeoff Apple makes; verify visually on a modern simulator during implementation, keep `usesMediumDetent` gated so it can be turned off without touching the editors.
- **Title re-expansion sensitivity**: the large title only re-expands at the exact top edge; users mid-scroll see the collapsed title. [Risk: perceived as "title disappeared"] → Mitigation: this is the native pattern; no action.
- **`NavigationView` vs `NavigationStack`**: scaffold continues using `NavigationView` for iOS 15 parity, as both editors do today. [Risk: deprecation warnings on modern OS] → Mitigation: none needed now; the scaffold is the single place to swap in `NavigationStack` behind an availability branch later.
- **Previews** use `AppContainer.production()`; the scaffold adds no DI, so previews migrate unchanged.

## Migration Plan

Single-step, in one change: create `EditorSheetScaffold`, migrate `CategoryEditorView` and `ActivityEditorView` in the same commit, update the two `Design/SCREENS/*.md` layout sections and add the `Design/COMPONENTS.md` contract plus `Design/DECISIONS.md` D33. Rollback is a straightforward revert of the same commit — no data or contract implications, backend untouched.

## Open Questions

None.
