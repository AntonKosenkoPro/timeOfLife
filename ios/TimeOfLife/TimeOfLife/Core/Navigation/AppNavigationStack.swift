import SwiftUI

/// iOS 15/16 navigation polyfill.
///
/// `NavigationStack` is iOS 16+; on iOS 15 we fall back to `NavigationView`
/// with `.stack` and a programmatic `NavigationLink` driven by the top of
/// `path`. Call sites stay identical; the underlying primitive is selected at
/// runtime.
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

    func popToRoot() {
        path.removeAll()
    }

    func popLast() {
        if !path.isEmpty { path.removeLast() }
    }

    /// Trims the stack so it contains exactly `count` routes. Used by the iOS 15
    /// navigation polyfill when a nested `NavigationLink` deactivates.
    func popTo(count: Int) {
        guard path.count > count else { return }
        path.removeSubrange(count...)
    }
}

/// SwiftUI container view that renders content inside the right primitive
/// for the current OS and binds to `AppNavigationStack.path`.
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
        if #available(iOS 16.0, *) {
            NavigationStack(path: $stack.path) {
                root()
                    .navigationDestination(for: AppRoute.self) { route in
                        destination(route)
                    }
            }
        } else {
            // iOS 15 fallback: nested `NavigationLink`s so each pushed route can
            // push the next one, preserving the stack up to `path.count`. The
            // root link covers index 0; each destination links to index + 1.
            NavigationView {
                root()
                    .background(
                        Group {
                            if !stack.path.isEmpty {
                                NavigationLink(
                                    destination: nestedDestination(at: 0),
                                    isActive: Binding(
                                        get: { !stack.path.isEmpty },
                                        set: { active in
                                            if !active { stack.popTo(count: 0) }
                                        }
                                    )
                                ) { EmptyView() }
                                .opacity(0)
                            }
                        }
                    )
            }
            .navigationViewStyle(.stack)
        }
    }

    /// Recursively builds the iOS 15 destination chain: the route at `index`
    /// carries a hidden link to `index + 1` so the system back button and
    /// swipe-back gesture traverse the stack in the same order as on iOS 16+.
    /// Returns `AnyView` because a recursive `@ViewBuilder` `some View` would
    /// define its opaque return type in terms of itself.
    private func nestedDestination(at index: Int) -> AnyView {
        AnyView(
            destination(stack.path[index])
                .background(
                    Group {
                        if index + 1 < stack.path.count {
                            NavigationLink(
                                destination: nestedDestination(at: index + 1),
                                isActive: Binding(
                                    get: { index + 1 < stack.path.count },
                                    set: { active in
                                        if !active { stack.popTo(count: index + 1) }
                                    }
                                )
                            ) { EmptyView() }
                            .opacity(0)
                        }
                    }
                )
        )
    }
}

/// A route-aware navigation link. On iOS 16+ uses value-based links (works
/// with `NavigationStack` + `navigationDestination`); on iOS 15 pushes via
/// the `AppNavigationStack` and renders the destination through a hidden
/// `NavigationLink`.
struct RouteLink<Label: View>: View {
    @ObservedObject var stack: AppNavigationStack
    let route: AppRoute
    @ViewBuilder var label: () -> Label

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationLink(value: route) { label() }
        } else {
            Button { stack.push(route) } label: { label() }
        }
    }
}
