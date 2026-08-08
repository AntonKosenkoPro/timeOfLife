import SwiftUI
import UIKit

/// The full-height Activity search presentation. Search remains native while
/// the result surface is ordinary sheet content so it can contain browse,
/// creation, restoration, and error states consistently on iOS 15 and later.
struct ActivitySearchSheet: View {
    @ObservedObject var vm: TrackViewModel
    let store: LocalStore
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        NavigationView {
            ActivitySearchSheetContainer(vm: vm, dismissSheet: dismiss)
                .navigationTitle(L10n.timerChooseActivity.text)
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: vm.searchQueryBinding,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: L10n.timerSearchPrompt.text
                )
                .alert(
                    L10n.timerSearchRestorePrompt.text,
                    isPresented: restorePromptBinding
                ) {
                    Button(L10n.timerSearchRestore.text) {
                        Task { await vm.restorePendingDeletion() }
                    }
                    Button(L10n.signOutCancel.text, role: .cancel) {}
                }
                .alert(
                    L10n.timerCollisionTitle.text,
                    isPresented: collisionBinding
                ) {
                    Button(L10n.timerCollisionUseExisting.text) {
                        vm.useExistingAfterCollision()
                    }
                    Button(L10n.timerCollisionKeepEditing.text) {
                        vm.keepEditingAfterCollision()
                    }
                    Button(L10n.signOutCancel.text, role: .cancel) {}
                } message: {
                    if let collision = vm.search.collision {
                        Text(String(format: L10n.timerCollisionMessage.text, collision.existing.name))
                    }
                }
        }
        .navigationViewStyle(.stack)
        .sheet(item: editorPresentation) { presentation in
            ActivityEditorView(
                store: store,
                prefilledName: presentation.draft.name,
                onSaved: { activity in
                    Task { await vm.saveConfiguredCreation(draft: presentation.draft, saved: activity) }
                },
                onCollision: { existing, draft in
                    vm.reportConfiguredCollision(existing: existing, draft: draft)
                }
            )
        }
    }

    private var restorePromptBinding: Binding<Bool> {
        Binding(
            get: { vm.pendingRestore != nil },
            set: { if !$0 { vm.dismissPendingRestore() } }
        )
    }

    private var collisionBinding: Binding<Bool> {
        Binding(
            get: { vm.search.collision != nil },
            set: { if !$0 { vm.dismissCollision() } }
        )
    }

    private var editorPresentation: Binding<ActivitySearchState.EditorPresentation?> {
        Binding(
            get: { vm.search.editor },
            set: { if $0 == nil { vm.dismissEditor() } }
        )
    }
}

private struct ActivitySearchSheetContainer: View {
    @ObservedObject var vm: TrackViewModel
    let dismissSheet: DismissAction

    var body: some View {
        ActivitySearchSearchStateObserver(vm: vm, dismissSheet: dismissSheet)
    }
}

/// Observes the native search environment from below `.searchable`. Cancel is
/// a presentation-level action in this flow, so leaving active search also
/// dismisses the sheet and restores the unmodified committed timer state.
private struct ActivitySearchSearchStateObserver: View {
    @ObservedObject var vm: TrackViewModel
    let dismissSheet: DismissAction
    @Environment(\.isSearching)
    private var isSearching
    @State private var didActivateSearch = false

    var body: some View {
        ActivitySearchContentView(vm: vm)
            .background(
                SearchFieldFocusBridge()
                    .frame(width: 1, height: 1)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            )
            .onChange(of: isSearching) { isActive in
                if isActive {
                    didActivateSearch = true
                } else if didActivateSearch {
                    vm.cancelSearch()
                    dismissSheet()
                }
            }
    }
}

/// SwiftUI does not expose a focus binding for `.searchable` on iOS 15. This
/// bridge targets the native `UISearchBar` after the searchable navigation
/// hierarchy has been installed, without replacing the system search field or
/// its placement and cancellation behavior.
private struct SearchFieldFocusBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> SearchFieldFocusView {
        SearchFieldFocusView()
    }

    func updateUIView(_ uiView: SearchFieldFocusView, context: Context) {
        uiView.requestFocus()
    }
}

private final class SearchFieldFocusView: UIView {
    private var focusAttempts = 0
    private var isWaitingForSearchField = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        requestFocus()
    }

    func requestFocus() {
        guard window != nil, !isWaitingForSearchField else { return }
        focusAttempts = 0
        isWaitingForSearchField = true
        attemptFocus()
    }

    private func attemptFocus() {
        guard let window else {
            isWaitingForSearchField = false
            return
        }

        if let searchBar = window.firstDescendant(of: UISearchBar.self) {
            if searchBar.isFirstResponder || searchBar.becomeFirstResponder() {
                isWaitingForSearchField = false
                return
            }
        }

        guard focusAttempts < 20 else {
            isWaitingForSearchField = false
            return
        }
        focusAttempts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.attemptFocus()
        }
    }
}

private extension UIView {
    func firstDescendant<T: UIView>(of type: T.Type) -> T? {
        if let match = self as? T {
            return match
        }
        for subview in subviews {
            if let match = subview.firstDescendant(of: type) {
                return match
            }
        }
        return nil
    }
}

#if DEBUG
#Preview("Search — Idle Empty") {
    let viewModel = TrackViewModel.preview(isSearchActive: true)
    return ActivitySearchSheet(vm: viewModel, store: viewModel.service.store)
}

#Preview("Search — Ready Prefilled") {
    let activity = Activity(id: "ready", name: "Deep work")
    let viewModel = TrackViewModel.preview(
        state: .ready(activity),
        activities: [activity],
        query: activity.name,
        isSearchActive: true
    )
    return ActivitySearchSheet(vm: viewModel, store: viewModel.service.store)
}

#Preview("Search — Collision") {
    let existing = Activity(id: "existing", name: "Gym")
    let collision = ActivitySearchState.CollisionPresentation(
        existing: existing,
        draft: ActivityDraft(name: "Gym", notes: "Leg day")
    )
    let viewModel = TrackViewModel.preview(
        state: .ready(existing),
        activities: [existing],
        isSearchActive: true,
        collision: collision
    )
    return ActivitySearchSheet(vm: viewModel, store: viewModel.service.store)
}
#endif
