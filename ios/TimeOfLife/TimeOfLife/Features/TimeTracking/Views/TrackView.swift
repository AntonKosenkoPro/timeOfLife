import SwiftUI

/// The Track capture screen (timer-capture-experience spec): a centered
/// numeric timer whose only purpose is displaying the exact duration while
/// the user chooses, starts, or stops an activity.
///
/// Content uses the adaptive dual-flow layout (refine-track-recents D1):
/// title → top spacer → completion mark → timer numbers/status → reserved
/// error region → central separator → Activity search/refine → main action →
/// Recents → bottom spacer → tab bar, with the top and bottom spacers capped
/// at 48 pt and surplus slack going to the central separator. Track itself
/// has no editing affordance and no offline hint.
///
/// Activity preparation uses a full-height native searchable sheet
/// (unify-activity-preparation-flow spec, decision 1). The operating system
/// owns the search field, focus, keyboard, and cancellation while Track keeps
/// its committed timer state untouched until a result is confirmed.
/// The Activity editor sheet and its presentation machinery remain wired for
/// the future editing placement (refine-track-recents D9, currently
/// unreachable from Track).
struct TrackView: View {
    @ObservedObject var vm: TrackViewModel
    @EnvironmentObject var container: AppContainer

    var body: some View {
        content
            .navigationTitle(L10n.tabTrack.text)
            .navigationBarTitleDisplayMode(.inline)
            .task { await vm.load() }
            .sheet(isPresented: searchPresentation, onDismiss: vm.cancelSearch) {
                ActivitySearchSheet(vm: vm)
                    .environmentObject(container)
            }
            .sheet(item: refinementPresentation, onDismiss: vm.dismissRefinement) { presentation in
                ActivityEditorView(
                    store: container.localStore,
                    activity: presentation.activity,
                    onSaved: { updated in
                        Task { await vm.saveRefinement(updated: updated) }
                    },
                    onCollision: { _ in
                        // The editor stays open with the draft intact; the
                        // editor's own error message surfaces the collision.
                    }
                )
                .environmentObject(container)
            }
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

    private var searchPresentation: Binding<Bool> {
        Binding(
            get: { vm.isSearchActive },
            set: { if !$0 { vm.cancelSearch() } }
        )
    }

    private var refinementPresentation: Binding<TrackViewModel.RefinementPresentation?> {
        Binding(
            get: { vm.refinementPresentation },
            set: { if $0 == nil { vm.dismissRefinement() } }
        )
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
    let activity = Activity(id: "preview-ready-en", name: "Deep work", categoryIDs: ["preview-c-work"])
    TrackContent(vm: .preview(
        state: .ready(activity),
        activities: [activity],
        categories: Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    ))
}

#Preview("Track — Running EN Light") {
    let activity = Activity(id: "preview-running", name: "Reading")
    TrackContent(vm: .preview(state: .running(activity, startedAt: Date().addingTimeInterval(-120)), activities: [activity]))
}

#Preview("Track — Saved EN Light") {
    let activity = Activity(id: "preview-saved", name: "Reading")
    TrackContent(vm: .preview(state: .saved(activity, duration: 65), activities: [activity]))
}

#Preview("Track — Error EN Light") {
    let activity = Activity(id: "preview-error", name: "Reading")
    let vm = TrackViewModel.preview(state: .error(activity, startedAt: Date().addingTimeInterval(-120)), activities: [activity])
    vm.errorMessage = L10n.text(in: .default, code: "error.unknown")
    return TrackContent(vm: vm)
}

#Preview("Track — Long Name, Empty Catalog") {
    let longName = String(repeating: "Very Long Activity Name ", count: 3)
    let activity = Activity(id: "preview-long", name: longName)
    TrackContent(vm: .preview(state: .ready(activity), activities: []))
}
#endif
