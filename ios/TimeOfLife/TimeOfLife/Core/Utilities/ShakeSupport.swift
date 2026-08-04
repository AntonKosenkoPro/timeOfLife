import SwiftUI
import UIKit

/// Shake-to-undo support (AC7 / U7).
///
/// U7 says "no custom shake detection" — use the iOS system motion event.
/// The view layer owns the binding:
/// - **iOS 17+:** a `.onShake` view modifier (see below).
/// - **iOS 15/16:** a `ShakeHostingController` subclass of `UIHostingController`
///   that overrides `motionEnded(_:with:)`. When the event is
///   `UIEvent.EventType.motion` and the subtype is `.motionShake`, it forwards
///   to the active manage screen's `performUndo()` via a shared observable
///   flag.
///
/// Do not implement custom accelerometer/gyro logic.

/// A shared observable flag that the `ShakeHostingController` sets when a
/// system shake motion event is received. Views observe it via `.onShake`.
@MainActor
final class ShakeMediator: ObservableObject {
    /// Increments on each shake. Views observe this via `.onChange`.
    @Published var shakeCount: Int = 0

    func handleShake() {
        shakeCount += 1
    }
}

/// `UIHostingController` subclass that forwards system shake motion events to
/// a `ShakeMediator`. Use it to wrap the signed-in navigation stack so both
/// `ManageActivitiesView` and `ManageCategoriesView` inherit the gesture.
final class ShakeHostingController<Content: View>: UIHostingController<Content> {
    private let mediator: ShakeMediator

    init(rootView: Content, mediator: ShakeMediator) {
        self.mediator = mediator
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    @MainActor
    dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeFirstResponder: Bool { true }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            Task { @MainActor in mediator.handleShake() }
        }
    }
}

/// A view modifier that observes the shared `ShakeMediator` and calls
/// `action` when a shake is detected. On iOS 17+, a native `.onShake`
/// modifier would be preferred; this implementation uses the mediator for
/// iOS 15/16 compatibility and works on all versions.
struct ShakeModifier: ViewModifier {
    @EnvironmentObject private var mediator: ShakeMediator
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: mediator.shakeCount) { _ in
            action()
        }
    }
}

extension View {
    /// Calls `action` when a system shake-to-undo motion event is received.
    /// Requires a `ShakeMediator` in the environment (injected by
    /// `ShakeHostingController`).
    func onShake(perform action: @escaping () -> Void) -> some View {
        modifier(ShakeModifier(action: action))
    }
}
