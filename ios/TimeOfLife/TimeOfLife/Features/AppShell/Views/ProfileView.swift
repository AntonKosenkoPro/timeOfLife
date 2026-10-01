import OSLog
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
    /// The last erase failure message, surfaced in an alert. Set only when
    /// `eraseLocalData()` throws — the file then survives on disk, so the
    /// flow stays signed in for a retry instead of logging out and
    /// reporting success.
    @State private var eraseErrorMessage: String?
    /// Last successful-sync date (fix-sync-status-row): feeds the age
    /// subtitle under "Syncing…" so the status row keeps its two-line height
    /// across states instead of jumping. Nil before the first sync.
    @State private var lastIdleDate: Date?

    private static let logger = Logger(subsystem: "com.antonkosenko.timeoflifeapp", category: "profile")

    /// Sign-out row contract (fix-profile-signout-row): shared `ListRow`
    /// geometry with a leading icon + danger tint, mirroring Erase local data.
    /// Pinned by `ProfileSignOutRowTests`; keep the icon + id in sync there.
    static let signOutIcon = "rectangle.portrait.and.arrow.right"
    static let signOutAccessibilityId = "ProfileSignOutButton"

    var body: some View {
        NavigationStack {
            List {
                accountSection
                onDeviceSection
                versionFooter
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
            .alert(
                L10n.profileEraseLocalData.text,
                isPresented: Binding(
                    get: { eraseErrorMessage != nil },
                    set: { if !$0 { eraseErrorMessage = nil } }
                )
            ) {
                Button(L10n.commonOk.text, role: .cancel) { eraseErrorMessage = nil }
            } message: {
                Text(eraseErrorMessage ?? "")
            }
        }
        .accessibilityIdentifier("Profile")
    }

    // MARK: - Account

    private var accountSection: some View {
        Section(L10n.profileAccount.text) {
            syncStatusRow
            Button(role: .destructive) {
                Task { await container.authService.logout() }
            } label: {
                ListRow(
                    title: L10n.profileSignOut.text,
                    icon: Self.signOutIcon,
                    tint: Theme.danger
                )
            }
            .accessibilityIdentifier(Self.signOutAccessibilityId)
        }
        // Remember the last idle date so the syncing/error branches can keep
        // the row's two-line height with real content (no layout jump).
        .onChange(of: sync.status, initial: true) { _, status in
            if case let .idle(date) = status {
                lastIdleDate = date
            }
        }
    }

    // Single TimelineView above the switch (fix-sync-status-row): the row must
    // keep one stable view structure across idle/syncing/error — swapping view
    // types or adding/removing the trailing button re-lays-out the section
    // and the screen jumps on every tap of Sync now.
    @ViewBuilder private var syncStatusRow: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            switch sync.status {
            case .inactive:
                EmptyView()
            case .syncing:
                ListRow(
                    title: L10n.profileSyncing.text,
                    icon: "arrow.triangle.2.circlepath",
                    subtitle: rememberedAgeSubtitle(now: context.date)
                ) {
                    syncButton(disabled: true)
                }
            case let .idle(date):
                ListRow(
                    title: L10n.profileSyncedSuccessfully.text,
                    icon: "checkmark.icloud",
                    subtitle: Self.ageSubtitle(since: date, now: context.date)
                ) {
                    syncButton(disabled: false)
                }
            case let .error(message):
                ListRow(
                    title: L10n.profileSyncError.text,
                    icon: "exclamationmark.icloud",
                    subtitle: message.isEmpty ? rememberedAgeSubtitle(now: context.date) : message
                ) {
                    syncButton(disabled: false)
                }
            }
        }
    }

    /// Trailing sync action on the status row (fix-sync-status-row): same
    /// call and automation id as the retired separate row. Present (disabled)
    /// while syncing so the row structure never changes between states.
    /// VoiceOver label reuses `profile.syncNow` — no new strings.
    private func syncButton(disabled: Bool) -> some View {
        Button {
            Task { await sync.syncNow(userID: sessionUserID) }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.body)
                .foregroundStyle(Theme.accentPrimary)
                .frame(minWidth: Theme.minTapArea, minHeight: Theme.minTapArea)
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        // `.disabled` alone does not restyle a custom label — without this
        // the button looks tappable while syncing (WelcomeView precedent).
        .opacity(disabled ? 0.6 : 1)
        .accessibilityIdentifier("ProfileSyncNowButton")
        .accessibilityLabel(L10n.profileSyncNow.text)
    }

    /// Age subtitle from a known date ("1 minute ago", "Меньше минуты назад").
    private static func ageSubtitle(since date: Date, now: Date) -> String {
        SyncRelativeTime.subtitle(
            since: date,
            now: now,
            ago: L10n.profileLastSyncedAgo.text,
            justNow: L10n.profileLastSyncedJustNow.text
        )
    }

    /// Age of the last successful sync, if any (nil before the first sync).
    private func rememberedAgeSubtitle(now: Date) -> String? {
        lastIdleDate.map { Self.ageSubtitle(since: $0, now: now) }
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

    /// Trailing diagnostic version footer (add-version-label-release): plain
    /// footer text with no row/card, so it stays dim and never reads as
    /// tappable. Plain `Text`, so VoiceOver exposes it as a static label.
    /// `.caption` scales with Dynamic Type; `Theme.textSecondary` resolves
    /// for light/dark.
    private var versionFooter: some View {
        Section {
            EmptyView()
        } footer: {
            Text(AppVersion.text)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("ProfileVersionLabel")
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
        // effect). A failed removal throws: log it, surface it, and stay
        // signed in so the user can retry — logging out anyway would strand
        // the surviving file as a dormant account with a success claim.
        // On success the store ends unbound; logout then clears the session
        // artifacts (Keychain tokens, cached session) and the gate
        // re-renders full-screen.
        do {
            try await container.eraseLocalData()
        } catch {
            Self.logger.error("Erase local data failed: \(String(describing: error), privacy: .public)")
            eraseErrorMessage = error.localizedDescription
            return
        }
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
