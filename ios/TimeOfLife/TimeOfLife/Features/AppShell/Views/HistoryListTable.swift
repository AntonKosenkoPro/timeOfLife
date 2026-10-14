import SwiftUI
import UIKit
import os

// MARK: - Bridge models

/// The table's section data: day label + tracked total + per-row display
/// values, built by `HistoryView` from its view model each render. The
/// representable diffs it and reloads only on change, so a re-render that
/// preserves content never rebuilds cells.
struct HistorySectionModel: Equatable {
    struct Row: Equatable {
        let entry: TimeEntry
        let icon: String
        let categoryNames: String
        let timeframeText: String
        let durationText: String
        let isInProgress: Bool
        let viaText: String
        let hasNotes: Bool
    }

    let id: String
    let title: String
    let subtitle: String
    let rows: [Row]
}

/// UIKit bridge for the History list: a plain-style `UITableView` whose
/// section headers pin below the navigation bar (Calendar-Agenda-like,
/// fix-history-sticky-headers). UIKit, not SwiftUI `List`: pinned SwiftUI
/// headers cannot clip scrolled rows on iOS 18 — cells composite above the
/// header view whatever background the header carries — and a custom
/// ScrollView loses the same clipping to overlay portals there.
///
/// Content stays SwiftUI (`EntryRow`, `SectionHeader`) through
/// `UIHostingConfiguration`, so the design-system components and their
/// accessibility are unchanged. The pinned header paints the opaque page
/// color, so it occludes rows scrolling beneath it while at rest it vanishes
/// against the page (no boxed look, no contrast with the navigation bar).
/// The table's frame stops at the safe area, so scrolled rows can never
/// reach the navigation bar or status bar. The list is read-only (no swipe
/// actions); a row tap and the pull-to-refresh land through the closures.
struct HistoryListTable: UIViewRepresentable {
    let sectionModels: [HistorySectionModel]
    let entryTapped: (TimeEntry) -> Void
    let refresh: () async -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            sectionModels: sectionModels,
            entryTapped: entryTapped,
            refresh: refresh
        )
    }

    func makeUIView(context: Context) -> UITableView {
        let table = UITableView(frame: .zero, style: .plain)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.separatorStyle = .none
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 66
        table.estimatedSectionHeaderHeight = 44
        table.backgroundColor = .clear
        table.accessibilityIdentifier = "HistoryList"
        let control = UIRefreshControl()
        control.addTarget(
            context.coordinator,
            action: #selector(Coordinator.refreshPulled),
            for: .valueChanged
        )
        table.refreshControl = control
        context.coordinator.table = table
        context.coordinator.apply(sectionModels, in: table)
        return table
    }

    func updateUIView(_ table: UITableView, context: Context) {
        let coordinator = context.coordinator
        coordinator.entryTapped = entryTapped
        coordinator.refresh = refresh
        coordinator.apply(sectionModels, in: table)
        coordinator.settleStaleRefresh(in: table)
    }

    @MainActor
    final class Coordinator: NSObject {
        private(set) var sectionModels: [HistorySectionModel]
        private var appliedSectionModels: [HistorySectionModel] = []
        var entryTapped: (TimeEntry) -> Void
        var refresh: () async -> Void
        /// True while a triggered pull is still resolving. `valueChanged`
        /// fires once the control arms — often with the finger still down —
        /// so a re-armed retrigger this quickly must not start a second
        /// flow whose await wedges the spinner.
        private(set) var refreshInFlight = false
        /// When the last refresh flow retired. A hard fling downward at the
        /// list top within this window rides the control's settle-back and
        /// can leave the offset frozen mid-stretch, so it is clamped to the
        /// top instead (see `scrollViewWillEndDragging`).
        private(set) var lastRefreshSettledAt = Date.distantPast
        private let logger = Logger(subsystem: "com.antonkosenko.timeoflifeapp", category: "history.list")
        weak var table: UITableView?

        init(
            sectionModels: [HistorySectionModel],
            entryTapped: @escaping (TimeEntry) -> Void,
            refresh: @escaping () async -> Void
        ) {
            self.sectionModels = sectionModels
            self.entryTapped = entryTapped
            self.refresh = refresh
        }

        func apply(_ models: [HistorySectionModel], in table: UITableView) {
            sectionModels = models
            defer { appliedSectionModels = models }
            guard models != appliedSectionModels else { return }
            table.reloadData()
        }

        @objc
        func refreshPulled() {
            guard !refreshInFlight else { return }
            refreshInFlight = true
            logger.debug("pull refresh triggered")
            Task { [weak self] in
                guard let self, let table = self.table else {
                    self?.refreshInFlight = false
                    return
                }
                await self.refresh()
                logger.debug("pull refresh resolved; endRefreshing on next tick")
                // The control may still be under an active drag when the
                // refresh resolves (it arms mid-gesture); let the runloop
                // settle a tick so the end is not swallowed by it.
                try? await Task.sleep(nanoseconds: 150_000_000)
                table.refreshControl?.endRefreshing()
                lastRefreshSettledAt = Date()
                self.refreshInFlight = false
            }
        }

        /// Cleanup net: SwiftUI re-renders after a flow's verdict (notice or
        /// error dialog) settles — end any refresh control that outlived its
        /// flow. Only runs when no flow is in flight.
        func settleStaleRefresh(in table: UITableView) {
            guard !refreshInFlight,
                  table.refreshControl?.isRefreshing == true else { return }
            logger.debug("ending stale refresh control")
            table.refreshControl?.endRefreshing()
            refreshInFlight = false
        }
    }
}

extension HistoryListTable.Coordinator: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        sectionModels.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sectionModels[section].rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HistoryEntryRow")
            ?? UITableViewCell(style: .default, reuseIdentifier: "HistoryEntryRow")
        let row = sectionModels[indexPath.section].rows[indexPath.row]
        cell.contentConfiguration = UIHostingConfiguration {
            EntryRow(
                entry: row.entry,
                icon: row.icon,
                categoryNames: row.categoryNames,
                timeframeText: row.timeframeText,
                durationText: row.durationText,
                isInProgress: row.isInProgress,
                viaText: row.viaText,
                hasNotes: row.hasNotes
            )
            .padding(.horizontal, Theme.spacingMedium)
        }
        .margins(.all, 0)
        // Transparent cell over the page color; the row content carries the
        // horizontal padding (the hosting configuration adds none).
        cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        entryTapped(sectionModels[indexPath.section].rows[indexPath.row].entry)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let sectionModel = sectionModels[section]
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: "HistoryDayHeader")
            ?? UITableViewHeaderFooterView(reuseIdentifier: "HistoryDayHeader")
        // Opaque page-color band: at rest it merges with the page; pinned at
        // the top it occludes the rows scrolling beneath (UIKit draws the
        // pinned header above cells — SwiftUI pinned headers never do on
        // iOS 18).
        view.contentConfiguration = UIHostingConfiguration {
            SectionHeader(
                title: sectionModel.title,
                subtitle: sectionModel.subtitle
            )
            .padding(.horizontal, Theme.spacingMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.backgroundPrimary)
        }
        .margins(.all, 0)
        return view
    }

    // MARK: Pull-to-refresh retirement

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        // A hard fling downward right after a refresh flow retires collides
        // with the snap-back: the fling target lands mid-stretch and the
        // rubber-band never finishes, freezing the offset until the next
        // touch. Steer such a fling to the list top instead — only when the
        // flow is already over (a live one keeps the control's hold).
        let control = (scrollView as? UITableView)?.refreshControl
        guard control?.isRefreshing != true,
              Date().timeIntervalSince(lastRefreshSettledAt) < 1,
              velocity.y < 0,
              targetContentOffset.pointee.y < 0 else { return }
        logger.debug("fling into the stretch after refresh; snapping to list top")
        targetContentOffset.pointee.y = -scrollView.adjustedContentInset.top
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        endRefreshIfIdle(in: scrollView)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        endRefreshIfIdle(in: scrollView)
    }

    // The control arms mid-gesture; a refresh that resolves while the finger
    // is still down calls endRefreshing into an active drag and UIKit drops
    // it — the control stays armed and the offset stays held. When the drag
    // itself ends with no flow left running, retire the control then.
    private func endRefreshIfIdle(in scrollView: UIScrollView) {
        guard !refreshInFlight else { return }
        let control = (scrollView as? UITableView)?.refreshControl
        guard control?.isRefreshing == true else { return }
        logger.debug("ending refresh at drag end")
        control?.endRefreshing()
    }
}
