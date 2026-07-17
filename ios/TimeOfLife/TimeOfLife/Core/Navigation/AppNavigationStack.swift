import SwiftUI

/// iOS 15/16 navigation polyfill.
///
/// `NavigationStack` is iOS 16+; on iOS 15 we fall back to `NavigationView`
/// with `.stack` and a programmatic `NavigationLink` driven by the top of
/// `path`. Call sites stay identical; the underlying primitive is selected at
/// runtime.
///
/// `AppNavigationStack` is the `ObservableObject` that owns the path so
/// `TimeOfLifeApp` can push deep-link routes into it.
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
            // iOS 15 fallback: NavigationView(.stack) with a hidden active link
            // that renders the top of `path`. RouteLink pushes by mutating
            // `path`; this link surfaces the destination.
            NavigationView {
                root()
                    .background(
                        Group {
                            if let top = stack.path.last {
                                NavigationLink(
                                    destination: destination(top),
                                    isActive: Binding(
                                        get: { !stack.path.isEmpty },
                                        set: { active in
                                            if !active { stack.popLast() }
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