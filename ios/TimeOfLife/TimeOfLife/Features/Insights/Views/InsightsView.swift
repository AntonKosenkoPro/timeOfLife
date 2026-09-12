import SwiftUI

/// Period-scoped breakdown of committed tracked time (insights-breakdown
/// spec). A read-only mirror: hero total plus proportional rows under a
/// period switch and a lens toggle. Rows are deliberately non-tappable and
/// the screen never judges (no percentages, targets, or comparisons).
///
/// Lifecycle mirrors `HistoryView`: guarded reload on appear, stale on leave,
/// and a refresh-signal reload so entries saved from the compact timer appear
/// without leaving the tab.
struct InsightsView: View {
    @StateObject private var vm: InsightsViewModel
    @State private var period: InsightsPeriod = .week
    @State private var lens: InsightsLens = .category
    /// Changes whenever the shell's running timer starts or stops (nil on
    /// stop). Lets Insights reload an entry saved from the compact timer
    /// without leaving the tab.
    private let refreshSignal: String

    init(store: LocalStore, refreshSignal: String = "") {
        _vm = StateObject(wrappedValue: InsightsViewModel(store: store))
        self.refreshSignal = refreshSignal
    }

    var body: some View {
        // ZStack, not Group: the lifecycle modifiers below must hang on a
        // structurally stable container (same rationale as HistoryView).
        ZStack {
            if !vm.hasLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !vm.hasCommittedAllTime {
                EmptyState(
                    icon: "chart.line.uptrend.xyaxis",
                    title: L10n.insightsEmptyTitle.text,
                    subtitle: L10n.insightsEmptySubtitle.text
                )
            } else {
                breakdownContent
            }
        }
        .background(Theme.backgroundPrimary.ignoresSafeArea())
        .task { await vm.loadIfNeeded() }
        .onAppear { Task { await vm.loadIfNeeded() } }
        .onDisappear { vm.invalidate() }
        .onChange(of: refreshSignal) { _ in
            vm.invalidate()
            Task { await vm.loadIfNeeded() }
        }
    }

    private var breakdownContent: some View {
        let breakdown = vm.breakdown(period: period, lens: lens)
        return ScrollView {
            VStack(spacing: Theme.spacingMedium) {
                periodPicker
                if breakdown.rows.isEmpty, let empty = period.emptyText {
                    Text(empty)
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.spacingLarge)
                } else {
                    hero(totalSeconds: breakdown.totalSeconds)
                    lensPicker
                    breakdownRows(breakdown)
                    if lens == .category {
                        Text(L10n.insightsFootnote.text)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal, Theme.spacingMedium)
            .padding(.vertical, Theme.spacingSmall)
        }
        .accessibilityIdentifier("InsightsList")
    }

    private var periodPicker: some View {
        Picker(period.label, selection: $period) {
            ForEach(InsightsPeriod.allCases) { item in
                Text(item.label).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("InsightsPeriodPicker")
    }

    private var lensPicker: some View {
        Picker(lens.label, selection: $lens) {
            ForEach(InsightsLens.allCases) { item in
                Text(item.label).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("InsightsLensPicker")
    }

    private func hero(totalSeconds: Int) -> some View {
        VStack(spacing: Theme.spacingExtraSmall) {
            Text(HistoryViewModel.naturalDuration(totalSeconds))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            Text("\(L10n.historyTracked.text) · \(period.label)")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .padding(.top, Theme.spacingSmall)
    }

    private func breakdownRows(_ breakdown: InsightsBreakdown) -> some View {
        let maxSeconds = breakdown.rows.map(\.totalSeconds).max() ?? 0
        return VStack(spacing: Theme.spacingSmall) {
            ForEach(breakdown.rows) { row in
                BreakdownRow(row: row, maxSeconds: maxSeconds)
            }
        }
    }
}

/// One breakdown row: icon, name, duration, and a proportional bar scaled to
/// the largest row (relative presence — never scaled to the hero, never
/// implying summation). Non-tappable by design (mirror-only spec).
private struct BreakdownRow: View {
    let row: InsightsBucket
    let maxSeconds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingExtraSmall) {
            HStack(spacing: Theme.spacingSmall) {
                Image(systemName: row.icon)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 24)
                Text(row.name)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(HistoryViewModel.naturalDuration(row.totalSeconds))
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                        .fill(Theme.backgroundSecondary)
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                        .fill(Theme.accentPrimary)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name), \(HistoryViewModel.naturalDuration(row.totalSeconds))")
        .accessibilityIdentifier("InsightsRow(\(row.id))")
    }

    private var fraction: Double {
        guard maxSeconds > 0 else { return 0 }
        return Double(row.totalSeconds) / Double(maxSeconds)
    }
}

#if DEBUG
#Preview("Insights") {
    let container = AppContainer.production()
    NavigationView {
        InsightsView(store: container.localStore)
    }
    .navigationViewStyle(.stack)
    .environmentObject(container)
}
#endif
