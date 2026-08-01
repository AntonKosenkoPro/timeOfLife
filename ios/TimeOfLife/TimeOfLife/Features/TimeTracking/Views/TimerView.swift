import SwiftUI

/// Main time-tracking screen.
///
/// Lets the user start a timer for an activity, see elapsed time, and stop
/// to save the entry. Entries are saved locally and synced when online.
///
/// The layout is intentionally stable: the timer display and the primary
/// control stay in the same position; only the button label/icon changes
/// between Start and Stop. This avoids layout jumps or trembling when the
/// timer starts/stops or when the keyboard appears. The activity field and
/// timer display live in a `ScrollView` in the upper portion of the screen,
/// while the Start/Stop button is pinned in a `.safeAreaInset(edge: .bottom)`
/// action bar that follows the keyboard.
struct TimerView: View {
    @ObservedObject var vm: TimerViewModel
    @EnvironmentObject var container: AppContainer
    @FocusState private var isActivityFocused: Bool

    @State private var showSignOutConfirm = false
    @State private var bottomBarHeight: CGFloat = 0

    var body: some View {
        // Use the shared navigation polyfill so catalog routes are rendered by
        // one container on both iOS 15 and iOS 16+.
        AppStack(
            stack: container.navigation,
            destination: { route in
                switch route {
                case .manageActivities:
                    manageActivitiesDestination
                case .manageCategories:
                    Text(L10n.manageActivitiesCategories.text)
                        .navigationTitle(L10n.manageActivitiesCategories.text)
                default:
                    EmptyView()
                }
            },
            root: { contentWithToolbar }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundPrimary.ignoresSafeArea())
        .task { await vm.refreshSuggestions() }
        .onChange(of: vm.isRunning) { running in
            if !running { Task { await vm.refreshSuggestions() } }
        }
    }

    /// The scrollable content plus the navigation title, Sign Out toolbar
    /// item, and confirmation alert. Shared by both the iOS 16 `NavigationStack`
    /// and the iOS 15 `NavigationView` fallback.
    private var contentWithToolbar: some View {
        content
            .navigationTitle(L10n.timerTitle.text)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.timerSignOut.text, role: .destructive) {
                        showSignOutConfirm = true
                    }
                    .font(.subheadline)
                    .accessibilityIdentifier("TimerSignOutButton")
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.timerManageActivities.text) {
                        container.navigation.push(.manageActivities)
                    }
                    .font(.subheadline)
                    .accessibilityIdentifier("TimerManageActivitiesButton")
                }
            }
            .alert(L10n.signOutConfirmationTitle.text, isPresented: $showSignOutConfirm) {
                Button(L10n.signOutConfirm.text, role: .destructive) {
                    Task { await vm.signOut() }
                }
                Button(L10n.signOutCancel.text, role: .cancel) {}
            } message: {
                Text(L10n.signOutConfirmationMessage.text)
            }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: Theme.spacingMedium) {
                Text(L10n.timerTitle.text)
                    .font(.title.bold())
                    .foregroundStyle(Theme.textPrimary)

                Spacer().frame(height: Theme.spacingExtraLarge)

                // Activity field row with quick-add button.
                HStack(spacing: Theme.spacingSmall) {
                    TextFieldWithError(
                        title: L10n.timerActivityPlaceholder.text,
                        placeholder: L10n.timerActivityPlaceholder.text,
                        text: $vm.activityName,
                        error: vm.fieldError,
                        keyboardType: .default,
                        textContentType: nil,
                        submitLabel: .done,
                        autocapitalization: .sentences,
                        accessibilityId: "TimerActivityField"
                    ) {
                        isActivityFocused = false
                        Task { await vm.start() }
                    }
                    .focused($isActivityFocused)
                    .disabled(vm.isRunning || vm.isLoading)

                    IconButton(
                        icon: "square.and.pencil",
                        accessibilityId: "TimerQuickAddButton",
                        isDisabled: vm.isRunning || vm.isLoading
                    ) {
                        vm.openQuickAdd()
                    }
                    .frame(width: Theme.minTapArea) // Stable frame prevents tremble
                }

                // Suggestions list — idle only.
                if vm.shouldShowSuggestions {
                    TimerSuggestionList(suggestions: vm.suggestions) { vm.prefill(from: $0) }
                }

                // Fixed-size stable timer display.
                Text(TimeFormatter.formattedDuration(vm.elapsed))
                    .font(Theme.timerFont())
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: .infinity)
                    .accessibilityIdentifier("TimerDisplay")

                Spacer().frame(height: Theme.spacingLarge)

                // Fixed reserve for the pinned bottom action bar so the
                // scrollable content ends well above the bar on every screen
                // size, even with the keyboard up.
                Color.clear.frame(height: bottomBarHeight + Theme.spacingLarge)
            }
            .padding(.horizontal, Theme.screenHorizontalPadding)
            .padding(.top, Theme.spacingExtraLarge)
            .frame(maxWidth: Theme.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundPrimary.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            // Pinned action bar. Content in `safeAreaInset` animates with the
            // system keyboard transition instead of reflowing with the main
            // stack, and stays visible above the keyboard so the user can tap
            // Start/Stop without dismissing the keyboard first.
            MeasuredBottomBar {
                VStack(spacing: Theme.spacingSmall) {
                    // This spacer makes the action bar taller, which in turn
                    // increases the ScrollView's bottom safe-area inset and
                    // keeps the activity field from crowding the primary
                    // button on small screens with the keyboard open.
                    Spacer().frame(height: Theme.spacingLarge)

                    if let errorMessage = vm.errorMessage {
                        ErrorBanner(message: errorMessage, accessibilityId: "TimerErrorBanner")
                    }
                    PrimaryButton(
                        title: vm.isRunning ? L10n.timerStop.text : L10n.timerStart.text,
                        icon: vm.isRunning ? "stop.fill" : "play.fill",
                        isLoading: vm.isLoading,
                        isDisabled: vm.isLoading || (!vm.isRunning && vm.activityName.trimmingCharacters(in: .whitespaces).isEmpty),
                        accessibilityId: vm.isRunning ? "TimerStopButton" : "TimerStartButton",
                        tint: vm.isRunning ? Theme.danger : Theme.accentPrimary
                    ) {
                        if vm.isRunning {
                            Task { await vm.stop() }
                        } else {
                            isActivityFocused = false
                            Task { await vm.start() }
                        }
                    }
                    .animation(nil, value: vm.isRunning)

                    if !container.connectivity.isConnected {
                        Text(L10n.timerOfflineHint.text)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("TimerOfflineHint")
                    }
                }
                .padding(.horizontal, Theme.screenHorizontalPadding)
                .padding(.vertical, Theme.spacingSmall)
                .frame(maxWidth: Theme.maxContentWidth)
                .frame(maxWidth: .infinity)
                .background(Theme.backgroundPrimary)
            }
        }
        .onPreferenceChange(BottomBarHeightPreferenceKey.self) { bottomBarHeight = $0 }
        .onAppear {
            isActivityFocused = true
            vm.isActivityFocused = true
        }
        .onChange(of: isActivityFocused) { vm.isActivityFocused = $0 }
        .onChange(of: vm.activityName) { _ in
            if vm.fieldError != nil {
                vm.fieldError = nil
            }
            if vm.errorMessage != nil {
                vm.errorMessage = nil
            }
        }
        .sheet(isPresented: $vm.showQuickAdd) {
            let editor = ActivityEditorViewModel(
                mode: .createFromTimer,
                store: container.catalogStore,
                repository: container.catalogRepository,
                service: container.catalogService,
                connectivity: container.connectivity
            )
            ActivityEditorView(vm: editor)
                .onChange(of: editor.onSaveResult) { result in
                    guard let result else { return }
                    switch result {
                    case let .created(activity, _), let .reused(activity), let .updated(activity):
                        vm.didSelectActivity(activity)
                    case .cancelled:
                        break
                    }
                }
        }
    }

    /// Catalog destination for the signed-in navigation stack.
    @ViewBuilder private var manageActivitiesDestination: some View {
        ManageActivitiesView(vm: ManageActivitiesViewModel(
            store: container.catalogStore,
            service: container.catalogService,
            repository: container.catalogRepository,
            undoBuffer: container.undoBuffer,
            entryCounter: container.activityEntryCounter
        ))
    }
}

/// Suggestion list rendered below the activity field when idle.
struct TimerSuggestionList: View {
    let suggestions: [Activity]
    let onTap: (Activity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingExtraSmall) {
            Text(L10n.timerSuggestionsHeader.text)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, Theme.spacingSmall)

            ForEach(suggestions, id: \.id) { activity in
                SuggestionRow(activity: activity) {
                    onTap(activity)
                }
            }
        }
        .padding(.vertical, Theme.spacingSmall)
        .padding(.horizontal, Theme.spacingSmall)
        .background(Theme.backgroundSecondary)
        .cornerRadius(Theme.cornerRadius)
        .accessibilityIdentifier("TimerSuggestionList")
    }
}

#if DEBUG
#Preview("Timer — EN Light") {
    let container = AppContainer.production()
    TimerView(vm: TimerViewModel(
        service: container.timerService,
        authService: container.authService,
        connectivity: container.connectivity,
        catalogStore: container.catalogStore,
        catalogService: container.catalogService
    ))
    .environmentObject(container)
}

#Preview("Timer — RU Dark") {
    let container = AppContainer.production()
    TimerView(vm: TimerViewModel(
        service: container.timerService,
        authService: container.authService,
        connectivity: container.connectivity,
        catalogStore: container.catalogStore,
        catalogService: container.catalogService
    ))
    .environmentObject(container)
    .preferredColorScheme(.dark)
    .environment(\.locale, .init(identifier: "ru"))
}

#Preview("Timer — Suggestions EN Light") {
    let container = AppContainer.production()
    let vm = TimerViewModel(
        service: container.timerService,
        authService: container.authService,
        connectivity: container.connectivity,
        catalogStore: container.catalogStore,
        catalogService: container.catalogService
    )
    vm.suggestions = [
        Activity(id: UUID(), name: "Reading", color: .blue, icon: .book,
                 notes: nil, lastUsedAt: Date(), categoryIds: [],
                 createdAt: Date(), updatedAt: Date()),
        Activity(id: UUID(), name: "Fitness", color: .green, icon: .figureRun,
                 notes: nil, lastUsedAt: Date().addingTimeInterval(-3600), categoryIds: [],
                 createdAt: Date(), updatedAt: Date()),
    ]
    return TimerView(vm: vm)
        .environmentObject(container)
}

#Preview("Timer — Suggestions RU Dark") {
    let container = AppContainer.production()
    let vm = TimerViewModel(
        service: container.timerService,
        authService: container.authService,
        connectivity: container.connectivity,
        catalogStore: container.catalogStore,
        catalogService: container.catalogService
    )
    vm.suggestions = [
        Activity(id: UUID(), name: "Чтение", color: .blue, icon: .book,
                 notes: nil, lastUsedAt: Date(), categoryIds: [],
                 createdAt: Date(), updatedAt: Date()),
        Activity(id: UUID(), name: "Фитнес", color: .green, icon: .figureRun,
                 notes: nil, lastUsedAt: Date().addingTimeInterval(-3600), categoryIds: [],
                 createdAt: Date(), updatedAt: Date()),
    ]
    return TimerView(vm: vm)
        .environmentObject(container)
        .preferredColorScheme(.dark)
        .environment(\.locale, .init(identifier: "ru"))
}
#endif
