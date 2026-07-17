import SwiftUI

/// Entry point of the Time of Life app.
///
/// Owns the composition root (`AppContainer`) and the deep-link entry point
/// for the `timeoflife://` URL scheme (`timeoflife://reset?token=` /
/// `timeoflife://verify?token=`).
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
                .onOpenURL { url in
                    handle(url: url)
                }
        }
    }

    /// Parses a `timeoflife://` deep link and pushes the matching route.
    private func handle(url: URL) {
        guard let route = DeepLink.parse(url: url) else { return }
        navigation.push(route)
    }
}

/// Pure parsing of `timeoflife://` deep links, factored out for unit testing.
enum DeepLink {
    static let scheme = "timeoflife"

    enum Host: String {
        case verify
        case reset
    }

    /// Returns the route for the URL, or `nil` if it isn't a recognized link.
    static func parse(url: URL) -> AppRoute? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        guard let host = url.host?.lowercased(), let kind = Host(rawValue: host) else {
            return nil
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let token = components?.queryItems?.first(where: { $0.name == "token" })?.value
        switch kind {
        case .verify:
            guard let token, !token.isEmpty else { return nil }
            return .verifyEmail(token: token)
        case .reset:
            guard let token, !token.isEmpty else { return nil }
            return .resetPassword(token: token)
        }
    }
}