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
        // `NavigationStack` is iOS 16+; fall back to `NavigationView(.stack)`
        // on iOS 15 so the toolbar still renders. The root content carries the
        // navigation title, toolbar, and sign-out alert. Both primitives are
        // bound to `container.navigation.path` so toolbar pushes actually render.
        Group {
            if #available(iOS 16, *) {
                NavigationStack(path: Binding(
                    get: { container.navigation.path },
                    set: { container.navigation.path = $0 }
                )) {
                    contentWithToolbar
                        .navigationDestination(for: AppRoute.self) { route in
                            switch route {
                            case .manageActivities:
                                manageActivitiesDestination
                            default:
                                EmptyView()
                            }
                        }
                }
            } else {
                NavigationView {
                    contentWithToolbar
                        .background(
                            NavigationLink(
                                destination: manageActivitiesDestination,
                                isActive: Binding(
                                    get: { container.navigation.path.last == .manageActivities },
                                    set: { active in
                                        if !active, !container.navigation.path.isEmpty {
                                            container.navigation.popToRoot()
                                        }
                                    }
                                )
                            ) { EmptyView() }
                            .opacity(0)
                        )
                }
                .navigationViewStyle(.stack)
            }
        }
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
                        vm.start()
                    }
                    .focused($isActivityFocused)
                    .disabled(vm.isRunning)

                    IconButton(
                        icon: "square.and.pencil",
                        accessibilityId: "TimerQuickAddButton",
                        isDisabled: vm.isRunning
                    ) {
                        vm.openQuickAdd()
                    }
                    .frame(width: Theme.minTapArea) // Stable frame prevents tremble
                }

                // Suggestions list — idle only.
                if !vm.isRunning && !vm.suggestions.isEmpty {
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

                    PrimaryButton(
                        title: vm.isRunning ? L10n.timerStop.text : L10n.timerStart.text,
                        icon: vm.isRunning ? "stop.fill" : "play.fill",
                        isLoading: vm.isLoading,
                        isDisabled: !vm.isRunning && vm.activityName.trimmingCharacters(in: .whitespaces).isEmpty,
                        accessibilityId: vm.isRunning ? "TimerStopButton" : "TimerStartButton",
                        tint: vm.isRunning ? Theme.danger : Theme.accentPrimary
                    ) {
                        if vm.isRunning {
                            Task { await vm.stop() }
                        } else {
                            isActivityFocused = false
                            vm.start()
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
        .onAppear { isActivityFocused = true }
        .onChange(of: vm.activityName) { _ in
            if vm.fieldError != nil {
                vm.fieldError = nil
            }
        }
        .sheet(isPresented: $vm.showQuickAdd) {
            // Quick-add sheet: ActivityEditor in create mode.
            // If 1-4 has not landed, this is a placeholder.
            ActivityEditorQuickAdd { activity in
                vm.didSelectNewActivity(activity)
            }
        }
    }

    /// Placeholder destination for `.manageActivities` until 1-4 lands.
    @ViewBuilder private var manageActivitiesDestination: some View {
        Text(L10n.timerManageActivities.text)
            .navigationTitle(L10n.timerManageActivities.text)
            .navigationBarTitleDisplayMode(.inline)
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

/// Placeholder quick-add sheet until 1-4's `ActivityEditor` lands.
/// Provides a simple text field to create a new activity with defaults.
struct ActivityEditorQuickAdd: View {
    let onSave: (Activity) -> Void
    @State private var name: String = ""
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(L10n.timerQuickAdd.text) {
                    TextField(L10n.timerActivityPlaceholder.text, text: $name)
                        .accessibilityIdentifier("QuickAddNameField")
                }
            }
            .navigationTitle(L10n.timerQuickAdd.text)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.signOutCancel.text) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.emailEntrySubmit.text) {
                        let activity = Activity(
                            id: UUID.v7(),
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            color: .mint,
                            icon: .clock,
                            notes: nil,
                            lastUsedAt: nil,
                            categoryIds: [],
                            createdAt: Date(),
                            updatedAt: Date()
                        )
                        onSave(activity)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
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
