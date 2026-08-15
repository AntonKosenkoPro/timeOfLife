import SwiftUI

/// The stable Track timer layout, built on the adaptive dual-flow stack
/// (refine-track-recents D1): navigation title, top spacer, completion mark,
/// timer numbers/status, reserved error region, central separator, Activity
/// search/refine, main action, Recents, bottom spacer, tab bar. The top and
/// bottom spacers share a 48 pt cap and split slack equally; surplus beyond
/// twice the cap goes to the central separator. D10 makes the content height
/// around the main action state-invariant (reserved idle preparation slot,
/// hidden-but-reserved Recents, fixed-height action slot) and pins the
/// bottom flow under wrapped-error growth. Activity-search draft state is
/// rendered in `ActivitySearchSheet`, rather than replacing this body.
struct TrackContent: View {
    @ObservedObject var vm: TrackViewModel
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize
    @State private var actionSlotWidth: CGFloat = 0
    @State private var measuredErrorRegionHeight: CGFloat = 0

    /// The spike-approved shared maximum for both adaptive spacers
    /// (refine-track-recents D1/D7).
    let spacerCap: CGFloat

    init(vm: TrackViewModel, spacerCap: CGFloat = 48) {
        self.vm = vm
        self.spacerCap = spacerCap
    }

    var body: some View {
        timerContent
            .background(Theme.backgroundPrimary.ignoresSafeArea())
            .onPreferenceChange(MainActionSlotWidthKey.self) { actionSlotWidth = $0 }
            .onPreferenceChange(TrackErrorRegionHeightKey.self) { measuredErrorRegionHeight = $0 }
    }

    // MARK: - Timer content

    private var timerContent: some View {
        AdaptiveVerticalLayout(
            spacerCap: spacerCap,
            topOverflow: topOverflow,
            topContent: { topFlow },
            bottomContent: { bottomFlow }
        )
    }

    // MARK: - Top flow

    private var topFlow: some View {
        VStack(spacing: 0) {
            completionMarkRegion
            NumericTimerReadout(state: vm.state, elapsed: vm.elapsed)
            errorRegion
                .padding(.top, Theme.spacingMedium)
        }
        .padding(.horizontal, Theme.screenHorizontalPadding)
        .frame(maxWidth: Theme.maxContentWidth)
        .frame(maxWidth: .infinity)
    }

    /// Reserved completion-mark region: keeps its height in every state and
    /// shows the saved checkmark without moving the timer below it.
    private var completionMarkRegion: some View {
        Color.clear
            .overlay {
                if case .saved = vm.state {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Theme.accentPrimary)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 28)
    }

    /// Reserved non-field-error region immediately above the search/refine
    /// flow. When empty it preserves geometry; when an error shows, the
    /// banner keeps its production identifier, wraps without being cut, and
    /// grows past the reserved height. Both branches measure their height so
    /// `topOverflow` (growth beyond the reservation) feeds the D10 pinned
    /// spacing model and resets to zero when the error clears.
    @ViewBuilder private var errorRegion: some View {
        if let errorMessage = vm.errorMessage {
            ErrorBanner(
                message: errorMessage,
                accessibilityId: "TrackErrorBanner"
            )
            .frame(minHeight: Self.errorRegionHeight, alignment: .top)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: TrackErrorRegionHeightKey.self,
                        value: geometry.size.height
                    )
                }
            )
        } else {
            Color.clear
                .frame(height: Self.errorRegionHeight)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: TrackErrorRegionHeightKey.self,
                            value: geometry.size.height
                        )
                    }
                )
        }
    }

    /// D10: the top flow's growth beyond its state-invariant baseline — the
    /// wrapped error region beyond its reservation. The pinned spacing model
    /// absorbs it from the top spacer first, then the central separator, so
    /// the main action stays stationary.
    private var topOverflow: CGFloat {
        max(0, measuredErrorRegionHeight - Self.errorRegionHeight)
    }

    /// Reserved error-region height: two scaled caption lines plus breathing
    /// room so a wrapped localized error stays inside the reservation.
    private static var errorRegionHeight: CGFloat {
        UIFontMetrics(forTextStyle: .caption1).scaledValue(for: 16) * 2 + Theme.spacingExtraSmall
    }

    // MARK: - Bottom flow

    private var bottomFlow: some View {
        VStack(spacing: 0) {
            activityPreparationControl
            primaryAction
                .padding(.top, Theme.spacingLarge)
            recentActivities
                .padding(.top, Theme.spacingLarge)
        }
        .padding(.horizontal, Theme.screenHorizontalPadding)
        .frame(maxWidth: Theme.maxContentWidth)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Activity preparation

    @ViewBuilder private var activityPreparationControl: some View {
        switch vm.state {
        case .idle:
            // D10: the slot is reserved in every state. The hidden picker
            // keeps the exact picker/label geometry but is invisible,
            // non-interactive, and absent from the accessibility tree.
            activityPicker
                .hidden()
                .accessibilityHidden(true)
        case .ready, .saved:
            activityPicker
        case .running, .saving, .error:
            preparedActivityLabel
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
                vm.activateSearch()
            case .ready, .saved:
                vm.start()
            case .running, .saving:
                Task { await vm.stop() }
            case .error:
                Task { await vm.retryStop() }
            }
        }
        .frame(height: actionSlotHeight)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: MainActionSlotWidthKey.self,
                    value: geometry.size.width
                )
            }
        )
        .accessibilityHint(primaryHint)
    }

    /// D10: the fixed-height slot for the state-specific main action. The
    /// slot equals the tallest title presentation at the active Dynamic
    /// Type size, so the Choose Activity / Start / Stop swap never resizes
    /// or moves the control.
    private var actionSlotHeight: CGFloat {
        MainActionSlot.height(
            titles: primaryTitles,
            width: actionSlotWidth,
            at: dynamicTypeSize
        )
    }

    private var primaryTitles: [String] {
        [L10n.timerChooseActivity.text, L10n.timerStart.text, L10n.timerStop.text]
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

    /// D10: Recents keeps its occupied height while hidden during running
    /// and error states, so the bottom content height is state-invariant and
    /// the adaptive spacers recompute identically — the main action above
    /// Recents does not move. Opacity-based hiding preserves layout on
    /// iOS 15; hit testing and accessibility are disabled while hidden, and
    /// the chips reappear in place for saving/saved.
    private var recentActivities: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text(L10n.timerChooserRecent.text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            if vm.activities.isEmpty {
                Text(L10n.timerRecentsEmptyHint.text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                RecentActivitiesChips(
                    activities: vm.activities,
                    categories: vm.categories,
                    selectedID: vm.state.activity?.id
                ) { vm.select($0) }
            }
        }
        .opacity(vm.state.isRunning ? 0 : 1)
        .allowsHitTesting(!vm.state.isRunning)
        .accessibilityHidden(vm.state.isRunning)
    }
}

private struct MainActionSlotWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TrackErrorRegionHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
