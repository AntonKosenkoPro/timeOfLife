import SwiftUI

/// The Track capture screen (timer-capture-experience spec): a centered
/// numeric timer whose only purpose is displaying the exact duration while
/// the user chooses, starts, or stops an activity.
///
/// Layout is intentionally stable: the activity affordance, numeric readout,
/// state label, and primary action keep their interaction regions across
/// idle, ready, running, saving, saved, and error states.
struct TrackView: View {
    @ObservedObject var vm: TrackViewModel
    @EnvironmentObject var container: AppContainer

    var body: some View {
        content
            .navigationTitle(L10n.tabTrack.text)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $vm.isChoosingActivity) {
                ActivityChooserView(vm: vm)
            }
            .task { await vm.load() }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                activityAffordance
                    .padding(.top, Theme.spacingMedium)

                NumericTimerReadout(state: vm.state, elapsed: vm.elapsed)
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
                    .padding(.top, Theme.spacingExtraLarge)

                primaryAction
                    .padding(.top, Theme.spacingLarge)

                if let errorMessage = vm.errorMessage {
                    ErrorBanner(
                        message: errorMessage,
                        accessibilityId: "TrackErrorBanner"
                    )
                    .padding(.top, Theme.spacingMedium)
                }

                if !vm.state.isRunning {
                    recentActivities
                        .padding(.top, Theme.spacingExtraLarge)
                } else {
                    Text(L10n.timerOfflineHint.text)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.spacingLarge)
                        .padding(.top, Theme.spacingLarge)
                }
            }
            .padding(.horizontal, Theme.screenHorizontalPadding)
            .padding(.bottom, Theme.spacingLarge)
            .frame(maxWidth: Theme.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundPrimary.ignoresSafeArea())
    }

    // MARK: - Activity affordance

    private var activityAffordance: some View {
        Button {
            vm.isChoosingActivity = true
        } label: {
            HStack(spacing: 7) {
                Text(vm.state.activity?.name ?? L10n.timerChooseActivity.text)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.headline)
            .foregroundStyle(Theme.textPrimary)
            .frame(minHeight: Theme.minTapArea)
        }
        .disabled(vm.state.isRunning)
        .opacity(vm.state.isRunning ? 0.72 : 1)
        .accessibilityIdentifier("TimerActivityPicker")
        .accessibilityLabel(vm.state.activity?.name ?? L10n.timerChooseActivity.text)
    }

    // MARK: - Primary action

    private var primaryAction: some View {
        PrimaryButton(
            title: primaryTitle,
            icon: primaryIcon,
            isLoading: vm.state.isSaving,
            isDisabled: primaryDisabled,
            accessibilityId: primaryIdentifier,
            tint: vm.state.isRunning ? Theme.danger : nil
        ) {
            switch vm.state {
            case .idle:
                vm.isChoosingActivity = true
            case .ready, .saved:
                vm.start()
            case .running:
                Task { await vm.stop() }
            case .saving:
                break
            case .error:
                Task { await vm.retryStop() }
            }
        }
        .accessibilityHint(primaryHint)
    }

    private var primaryTitle: String {
        switch vm.state {
        case .idle: L10n.timerChooseActivity.text
        case .ready, .saved: L10n.timerStart.text
        case .running, .saving: L10n.timerStop.text
        case .error: L10n.timerStop.text
        }
    }

    private var primaryIcon: String? {
        switch vm.state {
        case .idle: "plus"
        case .ready, .saved: "play.fill"
        case .running, .saving, .error: "stop.fill"
        }
    }

    private var primaryDisabled: Bool {
        switch vm.state {
        case .saving: true
        default: false
        }
    }

    private var primaryIdentifier: String {
        switch vm.state {
        case .idle: "TimerChooseActivityButton"
        case .ready, .saved: "TimerStartButton"
        case .running, .saving, .error: "TimerStopButton"
        }
    }

    private var primaryHint: String {
        switch vm.state {
        case .running, .saving, .error: L10n.timerStopHint.text
        default: ""
        }
    }

    // MARK: - Recent activities

    private var recentActivities: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            HStack {
                Text(L10n.timerChooserRecent.text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button(L10n.timerManageActivities.text) {
                    vm.isChoosingActivity = true
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.accentPrimary)
            }

            if vm.activities.isEmpty {
                Text(L10n.timerChooserEmptySubtitle.text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, Theme.spacingSmall)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.spacingSmall) {
                        ForEach(vm.activities.prefix(5)) { activity in
                            Button {
                                vm.select(activity)
                            } label: {
                                Text(activity.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(.horizontal, Theme.spacingMedium)
                                    .frame(height: Theme.minTapArea)
                                    .background(Theme.backgroundSecondary)
                                    .clipShape(Capsule())
                                    .overlay {
                                        Capsule().stroke(Theme.hairline, lineWidth: 0.7)
                                    }
                            }
                            .accessibilityLabel("Select \(activity.name)")
                            .accessibilityIdentifier("TimerSuggestion(\(activity.id))")
                        }
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Track — EN Light") {
    let container = AppContainer.production()
    TrackView(vm: TrackViewModel(
        service: container.timerService,
        connectivity: container.connectivity
    ))
    .environmentObject(container)
}

#Preview("Track — RU Dark") {
    let container = AppContainer.production()
    TrackView(vm: TrackViewModel(
        service: container.timerService,
        connectivity: container.connectivity
    ))
    .environmentObject(container)
    .preferredColorScheme(.dark)
    .environment(\.locale, .init(identifier: "ru"))
}
#endif
