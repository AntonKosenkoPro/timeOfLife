import SwiftUI

// MARK: - Pull notice (history-pull-to-sync)

/// Inline verdict below the navigation bar for offline pulls (one at a
/// time; newest pull wins). The signed-out notice is gone with the launch
/// gate — the only reachable signed-out surface is the auth gate itself.
/// `Theme` colors only.
struct PullNoticeBanner: View {
    var body: some View {
        Text(L10n.historyPullOffline.text)
            .font(.footnote)
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, Theme.spacingSmall)
            .padding(.horizontal, Theme.spacingMedium)
            .frame(maxWidth: .infinity)
            .background(Theme.backgroundSecondary)
            .accessibilityIdentifier("HistoryOfflineNotice")
    }
}
