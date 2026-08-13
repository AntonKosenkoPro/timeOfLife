## 1. Shared scaffold component

- [x] 1.1 Create `Core/Design/Components/EditorSheetScaffold.swift` per design D3: `NavigationView(.stack)`, `ScrollView` with standard padding (`Theme.screenHorizontalPadding` / `Theme.maxContentWidth`) and measured bottom-bar reserve, `.navigationBarTitleDisplayMode(.large)`, `navigationTitle`, Cancel `.cancellationAction` (disabled while `isLoading`, caller-supplied accessibility id), `measuredBottomBar`, `interactiveDismissDisabled(isLoading)`, and the `usesMediumDetent` iOS 16 `presentationDetents` availability branch
- [x] 1.2 Run `xcodegen generate` so the new file is part of the target; confirm `swiftlint lint --strict` passes

## 2. Migrate editors

- [x] 2.1 Migrate `CategoryEditorView` to the scaffold: move `L10n.categoryEditorCreateTitle` / `categoryEditorEditTitle` into the scaffold title, remove the custom `Text(...).font(.title.bold())` from content, keep `@FocusState`, `onAppear` focus, dismiss-on-save `onChange`, field content, and all accessibility identifiers unchanged
- [x] 2.2 Migrate `ActivityEditorView` to the scaffold the same way (edit/refine title, notes/categories content, nested `CategoryEditorView` sheet unchanged)
- [x] 2.3 Verify both editors visually on the iOS 15.5 simulator: at-rest large title + floating Cancel, collapse on scroll, re-expansion at top edge, Cancel dismissal, swipe-down dismiss, saving disabled state (spike app in `/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/T/opencode/spike-large-title` can be reused as a reference)
- [x] 2.4 Verify on a modern-runtime simulator: `.medium` detent presentation, keyboard-focus expansion, pinned Save bar above the keyboard with correct content reserve

## 3. Tests and docs

- [x] 3.1 Run `xcodebuild -scheme TimeOfLife -destination 'generic/platform=iOS Simulator' build` with zero warnings (project.yml treats warnings as errors)
- [x] 3.2 Run the iOS test suite (`xcodebuild test -scheme TimeOfLife -destination '<available simulator>'`) — `TrackViewModelRefinementTests` and catalog tests must stay green; add no new tests unless a behavior regression surfaces
- [x] 3.3 Update `Design/SCREENS/CategoryEditor.md` and `Design/SCREENS/ActivityEditor.md`: replace the custom-title layout item with the native collapsing header, keep the pinned-bar and keyboard sections
- [x] 3.4 Add the `EditorSheetScaffold` contract to `Design/COMPONENTS.md` (signature + when to use), per the "add it here first" rule
- [x] 3.5 Record D33 (native collapsing editor-sheet headers + shared scaffold) in `Design/DECISIONS.md`, citing this change's design.md
- [x] 3.6 Re-check the affected `Requirements/FURPS/*.md` rows (Activity_Catalog_and_Categories.md, Timetracking.md) for conflicts; update `docs/project-context.md` only if component standards need a pointer
- [x] 3.7 Run `openspec validate collapsing-editor-sheet-headers --strict` and mark all tasks `[x]`
