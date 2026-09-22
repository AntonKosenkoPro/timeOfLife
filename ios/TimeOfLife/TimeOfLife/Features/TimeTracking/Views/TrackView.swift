import SwiftUI

/// The Track capture screen (timer-capture-experience spec): a centered
/// numeric timer whose only purpose is displaying the exact duration while
/// the user enters, starts, or stops a name.
///
/// Content uses the adaptive dual-flow layout (refine-track-recents D1):
/// title → top spacer → completion mark → timer numbers/status → reserved
/// error region → central separator → name field → main action → running
/// tags / Recents → bottom spacer → tab bar, with the top and bottom
/// spacers capped at 48 pt and surplus slack going to the central separator.
/// Track itself has no editing affordance and no offline hint.
///
/// Capture is plain text (remove-activities-layer): no search sheet, no
/// quick-create, no refinement editor, no activity undo — typing is the only
/// input and the recents chips are exact-text shortcuts.
struct TrackView: View {
    @ObservedObject var vm: TrackViewModel

    var body: some View {
        content
            .navigationTitle(L10n.tabTrack.text)
            .navigationBarTitleDisplayMode(.inline)
            // First appear: pull recents + categories and restore a persisted
            // running draft. Returns to this tab refresh via AppShellView.
            .task { await vm.load() }
    }

    /// DEBUG-only spike gate: launching with `TRACK_SPIKE=1` replaces the
    /// Track content with the refine-track-recents layout harness (D7).
    @ViewBuilder private var content: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TRACK_SPIKE"] == "1" {
            TrackLayoutSpike()
        } else {
            TrackContent(vm: vm)
        }
        #else
        TrackContent(vm: vm)
        #endif
    }
}

#if DEBUG
#Preview("Track — Idle EN Light") {
    TrackContent(vm: .preview())
}

#Preview("Track — Ready EN Light") {
    let categories = [
        Category(id: "preview-c-work", name: "Work", icon: "laptopcomputer"),
        Category(id: "preview-c-study", name: "Study", icon: "book")
    ]
    TrackContent(vm: .preview(
        state: .ready(TrackState.Draft(text: "Deep work", categoryIDs: ["preview-c-work"])),
        recents: [
            TrackViewModel.RecentEntry(text: "Deep work", categoryIDs: ["preview-c-work"], firstCategoryID: "preview-c-work")
        ],
        categories: Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    ))
}

#Preview("Track — Running EN Light") {
    TrackContent(vm: .preview(
        state: .running(TrackState.Draft(text: "Reading"), startedAt: Date().addingTimeInterval(-120))
    ))
}

#Preview("Track — Saved EN Light") {
    TrackContent(vm: .preview(
        state: .saved(TrackState.Draft(text: "Reading"), duration: 65)
    ))
}

#Preview("Track — Error EN Light") {
    let vm = TrackViewModel.preview(
        state: .error(TrackState.Draft(text: "Reading"), startedAt: Date().addingTimeInterval(-120))
    )
    vm.errorMessage = L10n.text(in: .default, code: "error.unknown")
    return TrackContent(vm: vm)
}

#Preview("Track — Long Name, Empty Recents") {
    let longName = String(repeating: "Very Long Entry Name ", count: 3)
    TrackContent(vm: .preview(state: .ready(TrackState.Draft(text: longName)), recents: []))
}
#endif
