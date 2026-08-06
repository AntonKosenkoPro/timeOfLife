#if DEBUG
// This temporary, single-file design lab keeps the complete interactive flow
// easy to remove after production acceptance.
// swiftlint:disable file_length
import SwiftUI
import UIKit

enum DesignLabScreen {
    case trackLight
    case trackDark

    init?(screenName: String?) {
        switch screenName {
        case "design-track-light", "design-dial": self = .trackLight
        case "design-track-dark": self = .trackDark
        default: return nil
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .trackLight: .light
        case .trackDark: .dark
        }
    }
}

private struct PrototypeActivity: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let symbol: String
}

private enum PrototypeTab: Hashable {
    case track
    case history
    case insights
}

private enum PrototypeTimerState {
    case idle
    case ready(PrototypeActivity)
    case running(PrototypeActivity, Date)
    case saved(PrototypeActivity, TimeInterval)

    var activity: PrototypeActivity? {
        switch self {
        case .idle: nil
        case let .ready(activity), let .running(activity, _), let .saved(activity, _): activity
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

struct TrackDesignPrototype: View {
    let screen: DesignLabScreen

    @State private var selectedTab: PrototypeTab = .track
    @State private var timerState: PrototypeTimerState = .idle
    @State private var isChoosingActivity = false
    @State private var isShowingProfile = false

    private let activities = [
        PrototypeActivity(name: "Deep work", symbol: "circle.hexagongrid.fill"),
        PrototypeActivity(name: "Reading", symbol: "book.closed.fill"),
        PrototypeActivity(name: "Exercise", symbol: "figure.run"),
        PrototypeActivity(name: "Planning", symbol: "list.bullet.clipboard.fill")
    ]

    var body: some View {
        TabView(selection: $selectedTab) {
            navigationRoot {
                TrackPrototypeScreen(
                    state: timerState,
                    recentActivities: activities,
                    chooseActivity: { isChoosingActivity = true },
                    selectActivity: select,
                    primaryAction: performPrimaryAction
                )
            }
            .tabItem { Label("Track", systemImage: "timer") }
            .tag(PrototypeTab.track)
            .accessibilityIdentifier("DesignTrackTab")

            navigationRoot {
                DestinationPlaceholder(
                    title: "History",
                    symbol: "clock.arrow.circlepath",
                    message: "Your completed sessions will form a timeline here."
                )
                .safeAreaInset(edge: .bottom) { compactTimerIfNeeded }
            }
            .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            .tag(PrototypeTab.history)
            .accessibilityIdentifier("DesignHistoryTab")

            navigationRoot {
                DestinationPlaceholder(
                    title: "Insights",
                    symbol: "chart.line.uptrend.xyaxis",
                    message: "Patterns emerge after you have tracked a little time."
                )
                .safeAreaInset(edge: .bottom) { compactTimerIfNeeded }
            }
            .tabItem { Label("Insights", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(PrototypeTab.insights)
            .accessibilityIdentifier("DesignInsightsTab")
        }
        .tint(PrototypePalette.accent)
        .preferredColorScheme(screen.colorScheme)
        .sheet(isPresented: $isChoosingActivity) {
            ActivityChooserPrototype(activities: activities, onSelect: select)
        }
        .sheet(isPresented: $isShowingProfile) {
            ProfilePrototype()
                .preferredColorScheme(screen.colorScheme)
        }
    }

    @ViewBuilder
    private func navigationRoot<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationView {
            content()
                .navigationTitle(titleForSelectedTab)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { isShowingProfile = true } label: {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 19, weight: .regular))
                        }
                        .accessibilityLabel("Profile")
                        .accessibilityIdentifier("DesignProfileButton")
                    }
                }
        }
        .navigationViewStyle(.stack)
    }

    private var titleForSelectedTab: String {
        switch selectedTab {
        case .track: "Track"
        case .history: "History"
        case .insights: "Insights"
        }
    }

    @ViewBuilder private var compactTimerIfNeeded: some View {
        if case let .running(activity, startedAt) = timerState {
            CompactTimerPrototype(activity: activity, startedAt: startedAt) {
                selectedTab = .track
            } stop: {
                stop(activity: activity, startedAt: startedAt)
            }
        }
    }

    private func select(_ activity: PrototypeActivity) {
        timerState = .ready(activity)
        isChoosingActivity = false
    }

    private func performPrimaryAction() {
        switch timerState {
        case .idle:
            isChoosingActivity = true
        case let .ready(activity), let .saved(activity, _):
            UISelectionFeedbackGenerator().selectionChanged()
            timerState = .running(activity, Date())
        case let .running(activity, startedAt):
            stop(activity: activity, startedAt: startedAt)
        }
    }

    private func stop(activity: PrototypeActivity, startedAt: Date) {
        let duration = max(1, Date().timeIntervalSince(startedAt))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        timerState = .saved(activity, duration)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            guard case .saved = timerState else { return }
            timerState = .ready(activity)
        }
    }
}

private struct TrackPrototypeScreen: View {
    let state: PrototypeTimerState
    let recentActivities: [PrototypeActivity]
    let chooseActivity: () -> Void
    let selectActivity: (PrototypeActivity) -> Void
    let primaryAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text(statusEyebrow)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(statusColor)
                    .padding(.top, 8)

                Button(action: chooseActivity) {
                    HStack(spacing: 7) {
                        if let activity = state.activity {
                            Image(systemName: activity.symbol)
                        }
                        Text(state.activity?.name ?? "Choose an activity")
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.headline)
                    .foregroundStyle(PrototypePalette.primaryText)
                    .frame(minHeight: 44)
                }
                .disabled(state.isRunning)
                .opacity(state.isRunning ? 0.72 : 1)
                .accessibilityIdentifier("DesignActivityChooserButton")

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    TrackNumericPrototype(state: state, now: context.date)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .padding(.top, 34)

                primaryButton
                    .padding(.top, 24)

                if !state.isRunning {
                    recentActivitiesView
                        .padding(.top, 34)
                } else {
                    Text("You can move through the app. This timer stays with you.")
                        .font(.footnote)
                        .foregroundStyle(PrototypePalette.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .padding(.top, 26)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(PrototypePalette.canvas.ignoresSafeArea())
    }

    private var primaryButton: some View {
        Button(action: primaryAction) {
            HStack(spacing: 9) {
                Image(systemName: primarySymbol)
                    .font(.system(size: 13, weight: .bold))
                Text(primaryTitle)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(primaryForegroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(primaryColor)
            .clipShape(Capsule())
        }
        .accessibilityIdentifier(primaryIdentifier)
    }

    private var recentActivitiesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECENT")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(PrototypePalette.secondaryText)
                Spacer()
                Button("All activities", action: chooseActivity)
                    .font(.footnote.weight(.medium))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(recentActivities.prefix(3)) { activity in
                        Button { selectActivity(activity) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: activity.symbol)
                                    .foregroundStyle(PrototypePalette.accent)
                                Text(activity.name)
                                    .foregroundStyle(PrototypePalette.primaryText)
                            }
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 15)
                            .frame(height: 44)
                            .background(PrototypePalette.surface)
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().stroke(PrototypePalette.hairline, lineWidth: 0.7)
                            }
                        }
                        .accessibilityLabel("Select \(activity.name)")
                    }
                }
            }
        }
    }

    private var statusEyebrow: String {
        switch state {
        case .idle: "READY WHEN YOU ARE"
        case .ready: "READY"
        case .running: "IN PROGRESS"
        case .saved: "SAVED"
        }
    }

    private var statusColor: Color {
        state.isRunning ? PrototypePalette.accent : PrototypePalette.secondaryText
    }

    private var primaryTitle: String {
        switch state {
        case .idle: "Choose activity"
        case .ready: "Start"
        case .running: "Stop and save"
        case .saved: "Start again"
        }
    }

    private var primarySymbol: String {
        switch state {
        case .idle: "plus"
        case .ready, .saved: "play.fill"
        case .running: "stop.fill"
        }
    }

    private var primaryColor: Color {
        state.isRunning ? PrototypePalette.accent : PrototypePalette.primaryText
    }

    private var primaryForegroundColor: Color {
        state.isRunning ? .white : PrototypePalette.canvas
    }

    private var primaryIdentifier: String {
        switch state {
        case .idle: "DesignChooseActivityButton"
        case .ready, .saved: "DesignStartButton"
        case .running: "DesignStopButton"
        }
    }
}

private struct TrackNumericPrototype: View {
    let state: PrototypeTimerState
    let now: Date

    private var elapsed: TimeInterval {
        switch state {
        case let .running(_, startedAt): max(0, now.timeIntervalSince(startedAt))
        case let .saved(_, duration): duration
        case .idle, .ready: 0
        }
    }

    var body: some View {
        VStack(spacing: 9) {
            if case .saved = state {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(PrototypePalette.accent)
            }

            Text(formattedDuration(elapsed))
                .font(.system(size: 68, weight: .ultraLight, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PrototypePalette.primaryText)

            Text(numericCaption)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(PrototypePalette.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(formattedDuration(elapsed))
        .accessibilityIdentifier("DesignTrackNumericReadout")
    }

    private var numericCaption: String {
        switch state {
        case .idle: "NO ACTIVITY SELECTED"
        case .ready: "READY TO START"
        case .running: "ELAPSED"
        case .saved: "ENTRY SAVED"
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle: "Timer, no activity selected"
        case let .ready(activity): "Timer ready for \(activity.name)"
        case let .running(activity, _): "\(activity.name), timer running"
        case let .saved(activity, _): "\(activity.name), entry saved"
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%02d:%02d", minutes, remainder)
    }
}

private struct CompactTimerPrototype: View {
    let activity: PrototypeActivity
    let startedAt: Date
    let openTrack: () -> Void
    let stop: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 12) {
                Button(action: openTrack) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(PrototypePalette.accent.opacity(0.13))
                            Image(systemName: activity.symbol)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(PrototypePalette.accent)
                        }
                        .frame(width: 38, height: 38)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PrototypePalette.primaryText)
                            Text(formattedDuration(context.date.timeIntervalSince(startedAt)))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(PrototypePalette.secondaryText)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("\(activity.name), timer running")
                .accessibilityHint("Returns to Track")

                Button(action: stop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(PrototypePalette.accent)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Stop and save timer")
                .accessibilityIdentifier("DesignCompactStopButton")
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(height: 62)
            .background(PrototypePalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PrototypePalette.hairline, lineWidth: 0.7)
            }
            .shadow(color: PrototypePalette.shadow, radius: 12, y: 5)
            .padding(.horizontal, 12)
            .padding(.top, 6)
        }
        .background(PrototypePalette.canvas)
        .accessibilityIdentifier("DesignCompactTimer")
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct ActivityChooserPrototype: View {
    let activities: [PrototypeActivity]
    let onSelect: (PrototypeActivity) -> Void

    @Environment(\.dismiss)
    private var dismiss
    @State private var query = ""

    private var results: [PrototypeActivity] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return activities }
        return activities.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasExactMatch: Bool {
        activities.contains { $0.name.caseInsensitiveCompare(normalizedQuery) == .orderedSame }
    }

    var body: some View {
        NavigationView {
            List {
                Section(query.isEmpty ? "Recent" : "Activities") {
                    ForEach(results) { activity in
                        Button { onSelect(activity) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: activity.symbol)
                                    .foregroundStyle(PrototypePalette.accent)
                                    .frame(width: 24)
                                Text(activity.name)
                                    .foregroundStyle(PrototypePalette.primaryText)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(PrototypePalette.secondaryText)
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityLabel("Select \(activity.name)")
                    }

                    if !normalizedQuery.isEmpty && !hasExactMatch {
                        Button {
                            onSelect(PrototypeActivity(name: normalizedQuery, symbol: "sparkles"))
                        } label: {
                            Label("Create “\(normalizedQuery)”", systemImage: "plus.circle.fill")
                                .foregroundStyle(PrototypePalette.accent)
                                .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("DesignCreateActivityButton")
                    }
                }

                Section {
                    Button("Manage activities") {}
                }
            }
            .searchable(text: $query, prompt: "Search or create")
            .navigationTitle("Choose Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .accessibilityIdentifier("DesignActivityChooser")
    }
}

private struct DestinationPlaceholder: View {
    let title: String
    let symbol: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .ultraLight))
                .foregroundStyle(PrototypePalette.secondaryText)
            Text("Nothing here yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(PrototypePalette.primaryText)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(PrototypePalette.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PrototypePalette.canvas.ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), nothing here yet. \(message)")
    }
}

private struct ProfilePrototype: View {
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    Button {} label: {
                        HStack(spacing: 14) {
                            Image(systemName: "icloud")
                                .foregroundStyle(PrototypePalette.accent)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable Sync")
                                    .font(.body.weight(.semibold))
                                Text("Optional account for your other devices")
                                    .font(.caption)
                                    .foregroundStyle(PrototypePalette.secondaryText)
                            }
                        }
                        .frame(minHeight: 48)
                    }
                }

                Section("Library") {
                    Label("Activities", systemImage: "square.grid.2x2")
                    Label("Categories", systemImage: "tag")
                }

                Section("Connections") {
                    Label("Integrations", systemImage: "link")
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                Section("App") {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                    Label("Data and Privacy", systemImage: "hand.raised")
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .tint(PrototypePalette.accent)
        .accessibilityIdentifier("DesignProfile")
    }
}

// Dynamic UIKit colors preserve the prototype's custom palette in both appearances.
// swiftlint:disable object_literal
enum PrototypePalette {
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.025, green: 0.025, blue: 0.035, alpha: 1)
            : UIColor(red: 0.965, green: 0.960, blue: 0.948, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.075, green: 0.075, blue: 0.085, alpha: 1)
            : UIColor(red: 0.995, green: 0.992, blue: 0.982, alpha: 1)
    })
    static let primaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.96, green: 0.96, blue: 0.94, alpha: 1)
            : UIColor(red: 0.075, green: 0.075, blue: 0.082, alpha: 1)
    })
    static let secondaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.56, green: 0.55, blue: 0.58, alpha: 1)
            : UIColor(red: 0.43, green: 0.42, blue: 0.40, alpha: 1)
    })
    static let hairline = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.19, green: 0.19, blue: 0.21, alpha: 1)
            : UIColor(red: 0.82, green: 0.81, blue: 0.78, alpha: 1)
    })
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.27, blue: 0.23, alpha: 1)
            : UIColor(red: 0.93, green: 0.16, blue: 0.12, alpha: 1)
    })
    static let shadow = Color.black.opacity(0.16)
}
// swiftlint:enable object_literal

#endif
