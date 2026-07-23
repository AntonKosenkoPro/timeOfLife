import SwiftUI

/// Entry point of the Time of Life app.
///
/// Owns the composition root (`AppContainer`). Auth is passwordless: the user
/// enters their email, receives a 6-digit code, and types it on the OTP
/// screen to verify. There is no magic link / deep link — a custom URL scheme
/// only works in Apple Mail (Gmail/Outlook/Proton strip non-https schemes),
/// so the code is simply shown in the email body for the user to read and
/// type on every mail client.
@main
struct TimeOfLifeApp: App {
    @StateObject private var container: AppContainer
    @StateObject private var session: SessionStore
    @StateObject private var navigation: AppNavigationStack

    init() {
        let container = AppContainer.production()
        self._container = StateObject(wrappedValue: container)
        self._session = StateObject(wrappedValue: container.sessionStore)
        self._navigation = StateObject(wrappedValue: container.navigation)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                .environmentObject(session)
                .environmentObject(navigation)
                .preferredColorScheme(nil) // follow system
        }
    }
}
