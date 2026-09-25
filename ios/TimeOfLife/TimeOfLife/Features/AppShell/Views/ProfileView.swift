import SwiftUI

/// The Profile destination (app-shell spec): account + sync status, on-device
/// category management, and the destructive erase control. Signed-in only —
/// the launch gate guarantees a session, so there is no "Enable Sync" row and
/// no auth sheet. No activity management exists (no activity catalog —
/// remove-activities-layer).
struct ProfileView: View {
    @EnvironmentObject var container: AppContainer
    /// The signed-in session (Profile renders only behind the launch gate):
    /// supplies the `userId` the sync same-account guard checks against.
    @EnvironmentObject var session: SessionStore
    /// Observed directly (not via `container`): `AppContainer` publishes
    /// nothing, so nested reads like `container.syncController.status` never
    /// invalidate this view — the status row froze on "Syncing…" and the
    /// Sync now button never re-enabled. Separate environment objects (as in
    /// `TimeOfLifeApp`) subscribe to the real publishers.
    @EnvironmentObject var sync: SyncController
    @Environment(\.dismiss)
    private var dismiss
    @State private var isShowingEraseConfirm = false

    var body: some View {
        NavigationView {
            List {
                accountSection
                onDeviceSection
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
            syncStatusRow
            Button {
                Task { await sync.syncNow(userID: sessionUserID) }
            } label: {
                ListRow(title: L10n.profileSyncNow.text, icon: "arrow.triangle.2.circlepath")
            }
            .disabled(sync.status == .syncing)
            // `.disabled` alone does not restyle a custom label — without
            // this the button looks tappable while syncing (WelcomeView
            // precedent for the 0.6 value).
            .opacity(sync.status == .syncing ? 0.6 : 1)
            .accessibilityIdentifier("ProfileSyncNowButton")
            Button(L10n.timerSignOut.text, role: .destructive) {
                Task { await container.authService.logout() }
            }
            .accessibilityIdentifier("ProfileSignOutButton")
        }
    }

    @ViewBuilder private var syncStatusRow: some View {
        switch sync.status {
        case .inactive:
            EmptyView()
        case .syncing:
            ListRow(title: L10n.profileSyncing.text, icon: "arrow.triangle.2.circlepath")
        case let .idle(date):
            ListRow(
                title: String(format: L10n.profileLastSynced.text, Self.relativeTime(date)),
                icon: "checkmark.icloud"
            )
        case let .error(message):
            ListRow(
                title: L10n.profileSyncError.text,
                icon: "exclamationmark.icloud",
                subtitle: message.isEmpty ? nil : message
            )
        }
    }

    private static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - On This Device

    private var onDeviceSection: some View {
        Section(
            header: Text(L10n.profileOnDevice.text),
            footer: Text(L10n.profileOnDeviceFooter.text)
        ) {
            NavigationLink {
                ManageCategoriesView(
                    store: container.localStore,
                    undoBuffer: container.undoBuffer
                )
                .environmentObject(container)
            } label: {
                ListRow(title: L10n.profileCategories.text, icon: "tag")
            }
            .accessibilityIdentifier("ProfileCategoriesRow")
            Button(role: .destructive) {
                isShowingEraseConfirm = true
            } label: {
                ListRow(
                    title: L10n.profileEraseLocalData.text,
                    icon: "trash",
                    tint: Theme.danger
                )
            }
            .accessibilityIdentifier("ProfileEraseLocalDataButton")
        }
    }

    /// The authenticated session's `userId` (empty when signed out — Profile
    /// is unreachable then; the guard refuses an empty-id trigger anyway).
    private var sessionUserID: String {
        if case let .signedIn(current) = session.state { return current.id }
        return ""
    }

    private func eraseLocalData() async {
        // Deletes ONLY the active account's database file (account-bound-
        // store spec: explicit per-account erase, never a logout side
        // effect). The store ends unbound; logout then clears the session
        // artifacts (Keychain tokens, cached session) and the gate
        // re-renders full-screen.
        await container.eraseLocalData()
        await container.authService.logout()
        // Clear any stale auth routes (e.g. OTP for the erased account) so
        // the gate starts over from its first step (local-first-store
        // "Erase resets auth flow").
        container.navigation.path = []
    }
}

#if DEBUG
#Preview("Profile") {
    let container = AppContainer.production()
    ProfileView()
        .environmentObject(container)
        .environmentObject(container.sessionStore)
        .environmentObject(container.syncController)
}
#endif
