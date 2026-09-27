import SwiftUI

/// Navigation path ownership.
///
/// `AppNavigationStack` is the `ObservableObject` that owns the path so
/// `EmailEntryView` can push routes into it.
@MainActor
final class AppNavigationStack: ObservableObject {
    @Published var path: [AppRoute] = []

    init(path: [AppRoute] = []) {
        self.path = path
    }

    func push(_ route: AppRoute) {
        path.append(route)
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
