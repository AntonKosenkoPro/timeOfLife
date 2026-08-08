import SwiftUI

/// The Track capture screen (timer-capture-experience spec): a centered
/// numeric timer whose only purpose is displaying the exact duration while
/// the user chooses, starts, or stops an activity.
///
/// Layout is intentionally stable: the numeric readout and state-specific
/// preparation/primary controls keep their interaction regions across idle,
/// ready, running, saving, saved, and error states.
///
/// Activity preparation uses a full-height native searchable sheet
/// (unify-activity-preparation-flow spec, decision 1). The operating system
/// owns the search field, focus, keyboard, and cancellation while Track keeps
/// its committed timer state untouched until a result is confirmed.
struct TrackView: View {
    @ObservedObject var vm: TrackViewModel
    @EnvironmentObject var container: AppContainer

    var body: some View {
        TrackContent(vm: vm)
            .navigationTitle(L10n.tabTrack.text)
            .navigationBarTitleDisplayMode(.inline)
            .task { await vm.load() }
            .sheet(isPresented: searchPresentation, onDismiss: vm.cancelSearch) {
                ActivitySearchSheet(vm: vm, store: container.localStore)
                    .environmentObject(container)
            }
    }

    private var searchPresentation: Binding<Bool> {
        Binding(
            get: { vm.isSearchActive },
            set: { if !$0 { vm.cancelSearch() } }
        )
    }
}

/// The stable Track timer layout. Activity-search draft state is rendered in
/// `ActivitySearchSheet`, rather than replacing this body.
private struct TrackContent: View {
    @ObservedObject var vm: TrackViewModel

    var body: some View {
        timerContent
            .background(Theme.backgroundPrimary.ignoresSafeArea())
    }

    // MARK: - Timer content

    private var timerContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                NumericTimerReadout(state: vm.state, elapsed: vm.elapsed)
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
                    .padding(.top, Theme.spacingExtraLarge)

                activityPreparationControl
                    .padding(.top, Theme.spacingLarge)

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
    }

    // MARK: - Activity preparation

    @ViewBuilder private var activityPreparationControl: some View {
        switch vm.state {
        case .idle:
            chooseActivityButton
        case .ready, .saved:
            activityPicker
        case .running, .saving, .error:
            preparedActivityLabel
        }
    }

    private var chooseActivityButton: some View {
        PrimaryButton(
            title: L10n.timerChooseActivity.text,
            icon: "plus",
            isLoading: false,
            isDisabled: false,
            accessibilityId: "TimerChooseActivityButton"
        ) {
            vm.activateSearch()
        }
    }

    private var activityPicker: some View {
        Button {
            vm.activateSearch()
        } label: {
            HStack(spacing: Theme.spacingSmall) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
                Text(vm.state.activity?.name ?? L10n.timerSearchPrompt.text)
                    .lineLimit(1)
                    .foregroundStyle(vm.state.activity == nil ? Theme.textSecondary : Theme.textPrimary)
                Spacer()
            }
            .font(.body)
            .padding(.horizontal, Theme.spacingMedium)
            .frame(maxWidth: .infinity, minHeight: Theme.minTapArea)
            .background(Theme.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(Theme.hairline, lineWidth: 0.7)
            }
        }
        .disabled(vm.state.isRunning)
        .opacity(vm.state.isRunning ? 0.72 : 1)
        .accessibilityIdentifier("TimerActivitySearchButton")
        .accessibilityLabel(vm.state.activity?.name ?? L10n.timerSearchPrompt.text)
    }

    private var preparedActivityLabel: some View {
        HStack(spacing: Theme.spacingSmall) {
            Image(systemName: "timer")
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            Text(vm.state.activity?.name ?? L10n.timerSearchPrompt.text)
                .lineLimit(1)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .font(.body)
        .padding(.horizontal, Theme.spacingMedium)
        .frame(maxWidth: .infinity, minHeight: Theme.minTapArea)
        .background(Theme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.hairline, lineWidth: 0.7)
        }
        .accessibilityIdentifier("TimerActivityLabel")
        .accessibilityLabel(vm.state.activity?.name ?? L10n.timerSearchPrompt.text)
    }

    // MARK: - Primary action

    @ViewBuilder private var primaryAction: some View {
        if !isIdle {
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
                    break
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
    }

    private var isIdle: Bool {
        if case .idle = vm.state { return true }
        return false
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
            Text(L10n.timerChooserRecent.text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            if vm.activities.isEmpty {
                Text(L10n.timerSearchEmptyCatalogSubtitle.text)
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
                            .accessibilityLabel(String(format: L10n.timerSelectActivity.text, activity.name))
                            .accessibilityIdentifier("TimerSuggestion(\(activity.id))")
                        }
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Track — Idle EN Light") {
    TrackContent(vm: .preview())
}

#Preview("Track — Ready EN Light") {
    let activity = Activity(id: "preview-ready-en", name: "Deep work")
    TrackContent(vm: .preview(state: .ready(activity), activities: [activity]))
}

#Preview("Track — RU Dark") {
    let activity = Activity(id: "preview-ready", name: "Спортзал")
    TrackContent(vm: .preview(state: .ready(activity), activities: [activity]))
    .preferredColorScheme(.dark)
    .environment(\.locale, .init(identifier: "ru"))
}
#endif
