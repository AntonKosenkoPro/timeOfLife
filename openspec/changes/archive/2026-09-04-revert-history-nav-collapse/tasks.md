## 1. Revert nav-bar collapse in HistoryView

- [x] 1.1 Remove `.navigationBarHidden(!isScrolledToTop)` and the `isScrolledTo` state from `HistoryView.swift`
- [x] 1.2 Delete `ScrollViewTracker`, `TrackerView`, the collapse/restore threshold constants, and the `.background(ScrollViewTracker...)` wiring
- [x] 1.3 Rewrite `HistoryView` doc comments that justify the scroll-tracking/KVO approach (no stale references remain)
- [x] 1.4 Verify D8 elevated header total still works with the bar always visible (build + simulator pass on scroll)

## 2. Docs

- [x] 2.1 Update `Design/SCREENS/History.md` and `Design/README.md`: nav bar persistent, drop collapse description
- [x] 2.2 Update `docs/project-context.md` (history capability description, incomplete/deferred list if it mentions the collapse)

## 3. Quality gates

- [x] 3.1 `xcodegen generate` (no project.yml change expected) + `swiftlint lint --strict` green
- [x] 3.2 `xcodebuild test -scheme TimeOfLife` green (396+ tests)
- [x] 3.3 `openspec validate --changes revert-history-nav-collapse` green; simulator sanity pass (History at rest + scrolled: bar always visible, compact timer unaffected)
- [x] 3.4 Mark D9 in `openspec/changes/history-entry-list/design.md` as superseded by this change (note only, no behavior text edits)