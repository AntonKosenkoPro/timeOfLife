#if DEBUG
import SwiftUI

/// DEBUG-only layout spike harness for the refine-track-recents layout work
/// (design D1/D7/D8/D10). Renders the exact production `TrackContent`
/// dual-flow stack inside the real tab shell with a configurable spacer cap
/// and injected state, so the spike exercises the production invariants:
/// equal capped top/bottom spacers with central-separator surplus (D1), the
/// reserved error region (D8), and the state-invariant main-action frame
/// (D10 — reserved idle preparation slot, hidden-but-reserved Recents,
/// fixed-height action slot, top-first error yield). The large-type leg runs
/// the simulator's real content-size setting where possible (SE) and a
/// `.dynamicTypeSize(.accessibility5)` environment override elsewhere;
/// `RecentActivitiesChips` measures with a trait collection matching the
/// environment size, so chip packing never overruns under either path.
///
/// Configured per launch through `simctl launch` environment variables
/// (`SIMCTL_CHILD_` prefix):
///   TRACK_SPIKE=1              enables the harness (checked by TrackView)
///   TRACK_SPIKE_CAP=<pt>       shared spacer cap; default 48
///   TRACK_SPIKE_STATE=<name>   idle | ready | running | saving | saved | error
///   TRACK_SPIKE_DYNAMIC_TYPE=1 applies `.dynamicTypeSize(.accessibility5)`
///   TRACK_SPIKE_EMPTY=1        empty recents (empty-Recents hint)
///   TRACK_SPIKE_LONG_ERROR=1   a long error message (wrapped-error growth)
///
/// Frames are read from the accessibility tree via the production
/// identifiers (TimerDisplay, TimerNameField/TimerNameLabel,
/// TimerStartButton/TimerStopButton, TimerSuggestion(...)).
struct TrackLayoutSpike: View {
    private let cap: CGFloat
    private let dynamicType: Bool
    private let vm: TrackViewModel

    init() {
        let env = ProcessInfo.processInfo.environment
        cap = env["TRACK_SPIKE_CAP"].flatMap(Double.init).map { CGFloat($0) } ?? 48
        dynamicType = env["TRACK_SPIKE_DYNAMIC_TYPE"] == "1"
        let empty = env["TRACK_SPIKE_EMPTY"] == "1"
        let catalog = empty ? [] : Self.spikeRecents
        let categories = Dictionary(uniqueKeysWithValues: Self.spikeCategories.map { ($0.id, $0) })
        let state: TrackState
        if let prepared = catalog.first {
            let draft = TrackState.Draft(text: prepared.text, categoryIDs: prepared.categoryIDs)
            switch env["TRACK_SPIKE_STATE"] ?? "ready" {
            case "idle":
                state = .idle
            case "running":
                state = .running(draft, startedAt: Date().addingTimeInterval(-42))
            case "saving":
                state = .saving(draft, startedAt: Date().addingTimeInterval(-42))
            case "saved":
                state = .saved(draft, duration: 65)
            case "error":
                state = .error(draft, startedAt: Date().addingTimeInterval(-42))
            default:
                state = .ready(draft)
            }
        } else {
            state = .idle
        }
        let viewModel = TrackViewModel.preview(
            state: state,
            recents: catalog,
            categories: categories
        )
        if case .error = state {
            let message = L10n.text(in: .default, code: "error.unknown")
            viewModel.errorMessage = env["TRACK_SPIKE_LONG_ERROR"] == "1"
                ? String(repeating: "\(message) ", count: 8)
                : message
        }
        vm = viewModel
    }

    var body: some View {
        TrackContent(vm: vm, spacerCap: cap)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: SpikeViewportHeightKey.self,
                        value: geometry.size.height
                    )
                }
            )
            .onPreferenceChange(SpikeViewportHeightKey.self) { height in
                guard ProcessInfo.processInfo.environment["TRACK_SPIKE_DEBUG"] == "1" else { return }
                print("[SPIKE] viewportHeight=\(height)")
            }
            .dynamicTypeSize(dynamicType ? .accessibility5 : .large)
    }

    // MARK: - Fixtures

    private static var spikeCategories: [Category] {
        [
            Category(id: "spike-c-work", name: "Work", icon: "laptopcomputer"),
            Category(id: "spike-c-study", name: "Study", icon: "book"),
            Category(id: "spike-c-sport", name: "Sport", icon: "figure.run"),
            Category(id: "spike-c-mail", name: "Mail", icon: "briefcase"),
            Category(id: "spike-c-home", name: "Home", icon: "house"),
            Category(id: "spike-c-health", name: "Health", icon: "figure.mindandbody")
        ]
    }

    private static var spikeRecents: [TrackViewModel.RecentEntry] {
        [
            TrackViewModel.RecentEntry(text: "Deep work", categoryIDs: ["spike-c-work"], firstCategoryID: "spike-c-work"),
            TrackViewModel.RecentEntry(text: "Reading", categoryIDs: ["spike-c-study"], firstCategoryID: "spike-c-study"),
            TrackViewModel.RecentEntry(text: "Gym session", categoryIDs: ["spike-c-sport"], firstCategoryID: "spike-c-sport"),
            TrackViewModel.RecentEntry(text: "Emails", categoryIDs: ["spike-c-mail"], firstCategoryID: "spike-c-mail"),
            TrackViewModel.RecentEntry(text: "Walk the dog", categoryIDs: ["spike-c-home"], firstCategoryID: "spike-c-home"),
            TrackViewModel.RecentEntry(text: "Meditation", categoryIDs: ["spike-c-health"], firstCategoryID: "spike-c-health")
        ]
    }
}

private struct SpikeViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview("Track Spike — Ready, cap 48") {
    TrackLayoutSpike()
}
#endif
