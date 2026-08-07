import SwiftUI

/// The Profile destination (app-shell spec, D6/D30): useful without an
/// account. Account/sync controls live here alongside local activity and
/// category management, integrations, export, appearance, and data controls.
struct ProfileView: View {
    @EnvironmentObject var container: AppContainer
    @Environment(\.dismiss)
    private var dismiss
    @State private var isShowingEraseConfirm = false
    var body: some View {
        NavigationView {
            List {
                accountSection
                librarySection
                connectionsSection
                appSection
            }
            .navigationTitle(L10n.profileTitle.text)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.profileDone.text) { dismiss() }
                }
            }
            .alert(L10n.profileEraseLocalDataConfirmTitle.text, isPresented: $isShowingEraseConfirm) {
                Button(L10n.profileEraseConfirm.text, role: .destructive) {
                    Task { await eraseLocalData() }
                }
                Button(L10n.profileEraseCancel.text, role: .cancel) {}
            } message: {
                Text(L10n.profileEraseLocalDataConfirmMessage.text)
            }
        }
        .navigationViewStyle(.stack)
        .accessibilityIdentifier("Profile")
    }

    // MARK: - Account

    private var accountSection: some View {
        Section(L10n.profileAccount.text) {
            switch container.sessionStore.state {
            case .signedOut:
                Button {
                    Task { await container.authService.restoreSession() }
                } label: {
                    ListRow(
                        title: L10n.profileEnableSync.text,
                        icon: "icloud",
                        subtitle: L10n.profileEnableSyncSubtitle.text
                    )
                }
                .accessibilityIdentifier("ProfileEnableSyncButton")
            case .signedIn:
                syncStatusRow
                Button {
                    Task { await container.syncController.syncNow() }
                } label: {
                    ListRow(title: syncNowTitle, icon: "arrow.triangle.2.circlepath")
                }
                .disabled(container.syncController.status == .syncing)
                .accessibilityIdentifier("ProfileSyncNowButton")
                Button(L10n.timerSignOut.text, role: .destructive) {
                    Task { await container.authService.logout() }
                }
                .accessibilityIdentifier("ProfileSignOutButton")
            }
        }
    }

    @ViewBuilder private var syncStatusRow: some View {
        switch container.syncController.status {
        case .inactive:
            EmptyView()
        case .syncing:
            ListRow(title: L10n.profileSyncing.text, icon: "arrow.triangle.2.circlepath")
        case let .idle(date):
            ListRow(
                title: String(format: L10n.profileLastSynced.text, Self.relativeTime(date)),
                icon: "checkmark.icloud"
            )
        case .error:
            ListRow(title: L10n.profileSyncError.text, icon: "exclamationmark.icloud")
        }
    }

    private var syncNowTitle: String {
        container.syncController.status == .syncing ? L10n.profileSyncing.text : L10n.profileSyncNow.text
    }

    private static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Library

    private var librarySection: some View {
        Section(L10n.profileLibrary.text) {
            ListRow(title: L10n.profileActivities.text, icon: "square.grid.2x2")
            ListRow(title: L10n.profileCategories.text, icon: "tag")
        }
    }

    // MARK: - Connections

    private var connectionsSection: some View {
        Section(L10n.profileConnections.text) {
            ListRow(title: L10n.profileIntegrations.text, icon: "link")
            ListRow(title: L10n.profileExport.text, icon: "square.and.arrow.up")
        }
    }

    // MARK: - App

    private var appSection: some View {
        Section(L10n.profileApp.text) {
            ListRow(title: L10n.profileAppearance.text, icon: "circle.lefthalf.filled")
            ListRow(title: L10n.profileDataAndPrivacy.text, icon: "hand.raised")
            Button {
                isShowingEraseConfirm = true
            } label: {
                ListRow(title: L10n.profileEraseLocalData.text, icon: "trash")
                    .foregroundStyle(Theme.danger)
            }
            .accessibilityIdentifier("ProfileEraseLocalDataButton")
        }
    }

    private func eraseLocalData() async {
        do {
            try await container.localStore.eraseAll()
            await container.authService.logout()
        } catch {
            // Erase failure: keep the session; the user can retry.
        }
    }
}

#if DEBUG
#Preview("Profile") {
    let container = AppContainer.production()
    ProfileView()
        .environmentObject(container)
}
#endif
