import SwiftUI

/// Navigation path ownership.
///
/// `AppNavigationStack` is the `ObservableObject` that owns the path so
/// `EmailEntryView` can push routes into it.
@MainActor
final class AppNavigationStack: ObservableObject {
    @Published var path: [AppRoute] = []
    /// Monotonic counter bumped on every `lifio://track` deep link (Live
    /// Activity tap). `AppShellView` observes it and selects the Track tab.
    /// A counter (not a Bool) so rapid taps never coalesce.
    @Published var trackRequestID = 0
    /// Monotonic counter bumped on every Island-Stop link
    /// (`lifio://track?stop=1` — fix-terminated-stop-saved-face Spike D).
    /// `AppShellView` observes it, selects Track, reloads, and stops the
    /// timer through the exact in-app path. Counter (not Bool) so rapid
    /// taps never coalesce; a tap with no running draft is a graceful
    /// no-op at the stop call.
    @Published var islandStopRequestID = 0

    init(path: [AppRoute] = []) {
        self.path = path
    }

    func push(_ route: AppRoute) {
        path.append(route)
    }

    func requestTrack() {
        trackRequestID += 1
    }

    func requestIslandStop() {
        islandStopRequestID += 1
    }
}

/// SwiftUI container view that renders content inside a `NavigationStack`
/// bound to `AppNavigationStack.path`.
struct AppStack<Root: View, Destination: View>: View {
    @ObservedObject var stack: AppNavigationStack
    let destination: (AppRoute) -> Destination
    @ViewBuilder var root: () -> Root

    init(
        stack: AppNavigationStack,
        @ViewBuilder destination: @escaping (AppRoute) -> Destination,
        @ViewBuilder root: @escaping () -> Root
    ) {
        self.stack = stack
        self.destination = destination
        self.root = root
    }

    var body: some View {
        NavigationStack(path: $stack.path) {
            root()
                .navigationDestination(for: AppRoute.self) { route in
                    destination(route)
                }
        }
    }
}
