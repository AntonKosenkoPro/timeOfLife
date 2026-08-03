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
        // navigation title, toolbar, and sign-out alert.
        Group {
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
