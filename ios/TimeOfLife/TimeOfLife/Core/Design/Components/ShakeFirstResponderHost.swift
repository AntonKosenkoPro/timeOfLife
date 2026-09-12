import SwiftUI

/// Passive motion first-responder host for the system shake-to-undo (U7).
/// Surfaces without editable text hold no focus, so without this nothing is
/// first responder and shakes never reach the undo manager. The view is
/// transparent and background-placed (never intercepts touches), becomes
/// first responder when it enters the window (re-acquiring after
/// sheet/cover dismissals via `updateUIView`), and deliberately handles NO
/// motion itself — the shake propagates so the SYSTEM shows its default Undo
/// prompt for the action the owner registered.
///
/// It overrides `undoManager` to return the SAME instance the owner
/// registers with (`@Environment(\.undoManager)`): without this the shake
/// resolves up the responder chain (typically the window's manager), which
/// holds no registrations, so the system prompt never appears even though
/// the environment manager `canUndo`.
struct ShakeFirstResponderHost: UIViewRepresentable {
    var undoManager: UndoManager?

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.backgroundColor = .clear
        view.storedUndoManager = undoManager
        return view
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        uiView.storedUndoManager = undoManager
        if uiView.window != nil, !uiView.isFirstResponder {
            DispatchQueue.main.async {
                _ = uiView.becomeFirstResponder()
            }
        }
    }

    final class HostView: UIView {
        var storedUndoManager: UndoManager?
        override var canBecomeFirstResponder: Bool { true }
        override var undoManager: UndoManager? {
            storedUndoManager ?? super.undoManager
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                DispatchQueue.main.async { [weak self] in
                    _ = self?.becomeFirstResponder()
                }
            }
        }
    }
}
