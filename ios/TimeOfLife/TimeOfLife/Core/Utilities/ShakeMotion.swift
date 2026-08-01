import SwiftUI
import UIKit

extension Notification.Name {
    static let timeOfLifeDeviceDidShake = Notification.Name("TimeOfLifeDeviceDidShake")
}

/// Listens for the system motion bridge notification. The app may post this
/// notification from its hosting controller without adding a custom sensor.
struct ShakeMotionModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .timeOfLifeDeviceDidShake)
        ) { _ in
            action()
        }
    }
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        modifier(ShakeMotionModifier(action: action))
    }
}

/// iOS 15/16 bridge for the system motion event. No accelerometer polling or
/// custom shake detection is used; the responder system delivers the event.
struct ShakeMotionBridge: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ShakeHostingController {
        ShakeHostingController()
    }

    func updateUIViewController(_ controller: ShakeHostingController, context: Context) {}
}

final class ShakeHostingController: UIViewController {
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else { return }
        NotificationCenter.default.post(name: .timeOfLifeDeviceDidShake, object: nil)
        super.motionEnded(motion, with: event)
    }
}
