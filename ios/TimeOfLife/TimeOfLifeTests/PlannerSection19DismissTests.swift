import Testing
import Foundation
import SwiftUI
import UIKit
@testable import TimeOfLife

/// Day-planner §19 (hosted): the detached dismiss bump resigns the
/// composer field through the same `dismissID` path the circular × control
/// uses — without submitting. Split from `PlannerSection19Tests`
/// (file-length rule).
@MainActor
@Suite("Planner section 19 (detached dismiss hosting)", .serialized)
struct PlannerSection19DismissTests {
    @Test("a dismissID bump resigns the field without submitting")
    func dismissBumpResignsField() async throws {
        let driver = DismissDriver()
        let host = UIHostingController(rootView: DismissFieldHarness(driver: driver))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        defer { window.isHidden = true }
        let field = try #require(await composerField(in: host.view), "composer UITextField never materialized")
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(field.becomeFirstResponder())
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(field.isFirstResponder, "composer must hold focus")
        driver.bump()
        let deadline = Date().addingTimeInterval(5)
        while field.isFirstResponder, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(!field.isFirstResponder, "a dismiss bump must resign the field")
        #expect(driver.submits == 0, "a dismiss bump must not submit")
    }

    /// Polls the hosted hierarchy for the harness `UITextField` (day-planner
    /// 7.1 probe precedent): SwiftUI materializes it asynchronously after
    /// the window goes key.
    private func composerField(in root: UIView) async -> UITextField? {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let found = findComposerField(in: root) { return found }
            try? await Task.sleep(nanoseconds: 50_000_000)
            root.setNeedsLayout()
            root.layoutIfNeeded()
        }
        return nil
    }

    private func findComposerField(in view: UIView) -> UITextField? {
        if let field = view as? UITextField,
           field.accessibilityIdentifier == "PlannerComposerField" {
            return field
        }
        for subview in view.subviews {
            if let found = findComposerField(in: subview) { return found }
        }
        return nil
    }
}

/// A dismiss bump driver crossing the SwiftUI/test boundary
/// (Sendable-locked, so the hosted harness and the test share it without
/// actor-isolation friction).
private final class DismissDriver: @unchecked Sendable {
    private let lock = NSLock()
    private var bumpClosure: () -> Void = {}
    private var submitCount = 0

    var bump: () -> Void {
        get { lock.withLock { bumpClosure } }
        set { lock.withLock { bumpClosure = newValue } }
    }

    func noteSubmit() {
        lock.withLock { submitCount += 1 }
    }

    var submits: Int {
        lock.withLock { submitCount }
    }
}

/// A hosted bare composer field: the dismiss bump under test drives the
/// same `dismissID` path the detached control uses.
private struct DismissFieldHarness: View {
    @State var text = ""
    @State var dismissID = 0
    @FocusState var focused: Bool
    let driver: DismissDriver

    var body: some View {
        PlannerComposerField(
            text: $text,
            placeholder: "Add a task",
            focused: $focused,
            accessibilityIdentifier: "PlannerComposerField",
            dismissID: dismissID
        ) { driver.noteSubmit() }
        .onAppear { driver.bump = { dismissID += 1 } }
    }
}
