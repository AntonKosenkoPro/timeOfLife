import SwiftUI

/// Main time-tracking screen.
///
/// Lets the user start a timer for an activity, see elapsed time, and stop
/// to save the entry. Entries are saved locally and synced when online.
///
/// The layout is intentionally stable: the timer display and the primary
/// control stay in the same position; only the button label/icon changes
/// between Start and Stop. This avoids layout jumps or trembling when the
/// timer starts/stops or when the keyboard appears.
struct TimerView: View {
    @ObservedObject var vm: TimerViewModel
    @EnvironmentObject var container: AppContainer
    @FocusState private var isActivityFocused: Bool

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.backgroundPrimary.ignoresSafeArea())
    }

    private var content: some View {
        VStack(spacing: Theme.spacingMedium) {
            Spacer()

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

            // Primary control occupies the same slot; only label/icon change.
            PrimaryButton(
                title: vm.isRunning ? L10n.timerStop.text : L10n.timerStart.text,
                icon: vm.isRunning ? "stop.fill" : "play.fill",
                isLoading: vm.isLoading,
                isDisabled: !vm.isRunning && vm.activityName.trimmingCharacters(in: .whitespaces).isEmpty,
                accessibilityId: vm.isRunning ? "TimerStopButton" : "TimerStartButton"
            ) {
                if vm.isRunning {
                    Task { await vm.stop() }
                } else {
                    isActivityFocused = false
                    vm.start()
                }
            }
            .tint(vm.isRunning ? Theme.danger : Theme.accentPrimary)
            .animation(nil, value: vm.isRunning)

            Spacer()

            if !container.connectivity.isConnected {
                Text(L10n.timerOfflineHint.text)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("TimerOfflineHint")
            }
        }
        .padding(.horizontal, Theme.screenHorizontalPadding)
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
        connectivity: container.connectivity
    ))
    .environmentObject(container)
}

#Preview("Timer — RU Dark") {
    let container = AppContainer.production()
    TimerView(vm: TimerViewModel(
        service: container.timerService,
        connectivity: container.connectivity
    ))
    .environmentObject(container)
    .preferredColorScheme(.dark)
    .environment(\.locale, .init(identifier: "ru"))
}
#endif
