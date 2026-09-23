import Foundation
import Combine
import SwiftUI

/// Presentation logic for the Profile "Enable Sync" row (app-shell spec):
/// silent restore first, auth sheet only when still signed out; the sheet
/// clears on sign-in. Separated from `ProfileView` so the branching is
/// unit-testable — untestable branching is how the silent-no-op tap shipped.
@MainActor
final class EnableSyncPresenter: ObservableObject {
    @Published private(set) var isSheetPresented = false
    @Published private(set) var isRestoring = false

    private let authService: AuthService
    private let sessionStore: SessionStore
    private var cancellables = Set<AnyCancellable>()

    init(authService: AuthService, sessionStore: SessionStore) {
        self.authService = authService
        self.sessionStore = sessionStore
        // Dismiss observation: any sign-in path (OTP, Apple) flips the store
        // through `persist()`, so observing covers every success route.
        sessionStore.$state
            .sink { [weak self] state in
                guard state != .signedOut else { return }
                Task { @MainActor [weak self] in self?.dismiss() }
            }
            .store(in: &cancellables)
    }

    /// Runs on Enable Sync tap: silent restore, then the sheet iff the
    /// session is still signed out. Re-entrancy safe (row disables meanwhile).
    func enableSync() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        await authService.restoreSession()
        isSheetPresented = sessionStore.state == .signedOut
    }

    /// Closes the sheet (Cancel, swipe-to-dismiss binding, sign-in flip).
    /// Never touches session, store, or outbox state.
    func dismiss() {
        isSheetPresented = false
    }
}

/// Auth sheet for Enable Sync (app-shell spec): the existing auth flow with
/// sheet chrome. Shared by the Profile row and the History pull notice —
/// exactly one auth entry flow. Cancel and swipe-to-dismiss return unsigned
/// with local data untouched; any sign-in path clears the presenter's flag
/// and dismisses.
struct EnableSyncSheet: View {
    var body: some View {
        AuthFlowView()
            .accessibilityIdentifier("EnableSyncSheet")
    }
}
