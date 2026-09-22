import SwiftUI

/// The Profile destination (app-shell spec, D6/D30): useful without an
/// account. Account/sync controls live here alongside on-device category
/// management and the destructive erase control. No
/// activity management exists (no activity catalog — remove-activities-layer).
struct ProfileView: View {
    @EnvironmentObject var container: AppContainer
    /// Observed directly (not via `container`): `AppContainer` publishes
    /// nothing, so nested reads like `container.syncController.status` never
    /// invalidate this view — the status row froze on "Syncing…" and the
    /// Sync now button never re-enabled. Separate environment objects (as in
    /// `TimeOfLifeApp`) subscribe to the real publishers.
    @EnvironmentObject var sync: SyncController
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss)
    private var dismiss
    @State private var isShowingEraseConfirm = false
    /// Owns the Enable Sync tap branching (restore-then-sheet) and the
    /// sheet flag (app-shell spec). Constructed at the presentation site
    /// because `container` is not available in `init`.
    @StateObject private var enableSync: EnableSyncPresenter

    init(enableSync: EnableSyncPresenter) {
        _enableSync = StateObject(wrappedValue: enableSync)
    }
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
            // Enable Sync sheet (app-shell spec): the auth flow, presented
            // only when the silent restore left the session signed out.
            // The custom binding routes system dismissal through the
            // presenter; sign-in flips clear the flag from the presenter.
            .sheet(isPresented: Binding(
                get: { enableSync.isSheetPresented },
                set: { if !$0 { enableSync.dismiss() } }
            )) {
                EnableSyncSheet()
                    .environmentObject(container)
            }
        }
        .navigationViewStyle(.stack)
        .accessibilityIdentifier("Profile")
    }

    // MARK: - Account

    private var accountSection: some View {
        Section(L10n.profileAccount.text) {
            switch session.state {
            case .signedOut:
                Button {
                    Task { await enableSync.enableSync() }
                } label: {
                    ListRow(
                        title: L10n.profileEnableSync.text,
                        icon: "icloud",
                        subtitle: L10n.profileEnableSyncSubtitle.text
                    )
                }
                .disabled(enableSync.isRestoring)
                .accessibilityIdentifier("ProfileEnableSyncButton")
            case .signedIn:
                syncStatusRow
                Button {
                    Task { await sync.syncNow() }
                } label: {
                    ListRow(title: syncNowTitle, icon: "arrow.triangle.2.circlepath")
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

    /// The Sync Now action title never doubles as a status indicator — the
    /// status row above owns "Syncing…" alone (sync-client spec).
    private var syncNowTitle: String {
        L10n.profileSyncNow.text
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

    private func eraseLocalData() async {
        do {
            try await container.localStore.eraseAll()
            await container.authService.logout()
            // Stale auth routes (e.g. OTP for the erased account) would otherwise
            // re-present in the next Enable Sync sheet; shell tabs keep their own
            // NavigationViews, so this only clears the auth sheet's path.
            container.navigation.path = []
        } catch {
            // Erase failure: keep the session; the user can retry.
        }
    }
}

/// Auth sheet for Enable Sync (app-shell spec): the existing auth flow with
/// sheet chrome. Cancel and swipe-to-dismiss return unsigned with local data
/// untouched; any sign-in path clears the presenter's flag and dismisses.
private struct EnableSyncSheet: View {
    var body: some View {
        AuthFlowView()
            .accessibilityIdentifier("EnableSyncSheet")
    }
}

#if DEBUG
#Preview("Profile") {
    let container = AppContainer.production()
    ProfileView(enableSync: EnableSyncPresenter(
        authService: container.authService,
        sessionStore: container.sessionStore
    ))
    .environmentObject(container)
    .environmentObject(container.sessionStore)
    .environmentObject(container.syncController)
}
#endif
