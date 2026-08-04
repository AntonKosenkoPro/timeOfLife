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
    private let embeddedInNavigation: Bool
    @FocusState private var isActivityFocused: Bool

    @State private var showSignOutConfirm = false
    @State private var bottomBarHeight: CGFloat = 0

    init(vm: TimerViewModel, embeddedInNavigation: Bool = false) {
        self.vm = vm
        self.embeddedInNavigation = embeddedInNavigation
    }

    var body: some View {
        Group {
            if embeddedInNavigation {
                contentWithToolbar
            } else {
                // `NavigationStack` is iOS 16+; fall back to `NavigationView(.stack)`
                // on iOS 15 so the toolbar still renders. The root content carries the
                // navigation title, toolbar, and sign-out alert.
                if #available(iOS 16, *) {
                    NavigationStack {
                        contentWithToolbar
                    }
                } else {
                    NavigationView {
                        contentWithToolbar
                    }
                    .navigationViewStyle(.stack)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundPrimary.ignoresSafeArea())
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
                    Button {
                        container.navigation.push(.manageActivities)
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.subheadline)
                    }
                    .accessibilityIdentifier("TimerManageActivitiesButton")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.timerSignOut.text, role: .destructive) {
                        showSignOutConfirm = true
                    }
                    .font(.subheadline)
                    .accessibilityIdentifier("TimerSignOutButton")
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
                    .disabled(vm.isRunning)

                    // Quick-add button (F7) — disabled while running.
                    Button {
                        isActivityFocused = false
                        vm.isQuickAddPresented = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.title3)
                            .foregroundStyle(Theme.accentPrimary)
                    }
                    .disabled(vm.isRunning)
                    .accessibilityIdentifier("TimerQuickAddButton")
                }

                // Suggestions block (F5) — idle only, prefix matching.
                if !vm.isRunning && !vm.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                        Text(L10n.timerSuggestionsHeader.text)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityIdentifier("TimerSuggestionList")

                        ForEach(vm.suggestions) { activity in
                            Button {
                                vm.selectSuggestion(activity)
                            } label: {
                                HStack(spacing: Theme.spacingSmall) {
                                    Text(activity.name)
                                        .font(.body)
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    if let lastUsed = activity.lastUsedAt {
                                        Text(lastUsed, style: .relative)
                                            .font(.caption)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }
                                .padding(.vertical, Theme.spacingSmall)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("TimerSuggestion(\(activity.id))")
                        }
                    }
                }

                // Fixed-size stable timer display.
                Text(TimeFormatter.formattedDuration(vm.elapsed))
                    .font(Theme.timerFont())
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: .infinity)
                    .accessibilityIdentifier("TimerDisplay")

                Spacer().frame(height: Theme.spacingLarge)

                // Fixed reserve for the pinned bottom action bar.
                Color.clear.frame(height: bottomBarHeight + Theme.spacingLarge)
            }
            .padding(.horizontal, Theme.screenHorizontalPadding)
            .padding(.top, Theme.spacingExtraLarge)
            .frame(maxWidth: Theme.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            MeasuredBottomBar {
                VStack(spacing: Theme.spacingSmall) {
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
            Task { await vm.loadSuggestions() }
        }
        .onChange(of: vm.activityName) { _ in
            if vm.fieldError != nil {
                vm.fieldError = nil
            }
            Task { await vm.refreshSuggestions() }
        }
        .onChange(of: container.isCatalogReady) { isReady in
            if isReady {
                Task { await vm.loadSuggestions() }
            }
        }
        .sheet(isPresented: $vm.isQuickAddPresented) {
            // Quick-add sheet — Phase 8 will present the real ActivityEditorView.
            // For now, a placeholder that lets the user create a simple activity.
            QuickAddSheet(vm: vm)
        }
    }
}

#if DEBUG
#Preview("Timer — EN Light") {
    let container = AppContainer.production()
    TimerView(vm: TimerViewModel(
        service: container.timerService,
        authService: container.authService,
        connectivity: container.connectivity
    ))
    .environmentObject(container)
}

#Preview("Timer — RU Dark") {
    let container = AppContainer.production()
    TimerView(vm: TimerViewModel(
        service: container.timerService,
        authService: container.authService,
        connectivity: container.connectivity
    ))
    .environmentObject(container)
    .preferredColorScheme(.dark)
    .environment(\.locale, .init(identifier: "ru"))
}
#endif

/// Quick-add sheet — creates a new activity from the timer.
/// Phase 8 will replace this with the real `ActivityEditorView` in
/// create-from-timer mode.
private struct QuickAddSheet: View {
    @ObservedObject var vm: TimerViewModel
    @Environment(\.dismiss)
    private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationView {
            VStack(spacing: Theme.spacingMedium) {
                TextFieldWithError(
                    title: L10n.timerActivityPlaceholder.text,
                    placeholder: L10n.timerActivityPlaceholder.text,
                    text: $name,
                    error: nil,
                    keyboardType: .default,
                    textContentType: nil,
                    submitLabel: .done,
                    autocapitalization: .sentences,
                    accessibilityId: "QuickAddActivityField"
                ) {
                    save()
                }

                PrimaryButton(
                    title: L10n.timerStart.text,
                    icon: "plus",
                    isLoading: false,
                    isDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty,
                    accessibilityId: "QuickAddSaveButton"
                ) {
                    save()
                }
                Spacer()
            }
            .padding(.horizontal, Theme.screenHorizontalPadding)
            .padding(.top, Theme.spacingLarge)
            .navigationTitle(L10n.timerQuickAdd.text)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // Create a simple activity placeholder — Phase 8 will use the real
        // ActivityEditorView with full validation + sync.
        let activity = Activity(
            id: UUIDv7.generate(),
            name: trimmed,
            notes: nil,
            lastUsedAt: nil,
            createdAt: Date(),
            updatedAt: Date(),
            categoryIds: [],
            sync: .newPending()
        )
        vm.didSelectNewActivity(activity)
        dismiss()
    }
}
