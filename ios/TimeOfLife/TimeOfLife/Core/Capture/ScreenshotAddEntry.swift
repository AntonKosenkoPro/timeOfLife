#if SCREENSHOT_CAPTURE
import SwiftUI

/// Add-entry frame support (screenshot-capture spec): the genuine Log Time
/// sheet prefilled with the fixture sample (all five cards — Name, Start,
/// End, Categories, Notes — with a visible notes value). Draft-only: the
/// sample is never saved, so the 55-entry committed totals stay identical.
/// Gated: absent from shipping builds.
@MainActor
enum ScreenshotAddEntry {
    /// Builds the sheet's form through the public draft API — the same path
    /// the UI uses (notes assign directly, times through the picker
    /// setters: Start first since it shifts End, then End). Minute-exact
    /// fixture values pass through unchanged.
    static func makeForm(service: TimerService, request: ScreenshotCaptureRequest) -> LogTimeViewModel {
        let interval = ScreenshotFixture.addEntryInterval(
            calendar: request.calendar,
            referenceDate: request.referenceDate
        )
        let form = LogTimeViewModel(
            service: service,
            initialText: ScreenshotFixture.addEntryText(for: request.localeIdentifier),
            initialCategoryIDs: ScreenshotFixture.addEntryCategoryIDs(for: request.localeIdentifier)
        )
        form.notes = ScreenshotFixture.addEntryNotes(for: request.localeIdentifier)
        form.setStartsAt(interval.start)
        form.setEndsAt(interval.end)
        return form
    }

    /// Fails closed unless the sample satisfies the form's own validity
    /// gate — the spec's "validated state", never a mock drawing.
    static func validate(request: ScreenshotCaptureRequest, container: AppContainer) throws {
        let interval = ScreenshotFixture.addEntryInterval(
            calendar: request.calendar,
            referenceDate: request.referenceDate
        )
        guard interval.end > interval.start else {
            throw ScreenshotRequestError(code: "add-entry-invalid", detail: "Add-entry sample interval is not positive.")
        }
        let form = makeForm(service: container.timerService, request: request)
        guard !form.trimmedName.isEmpty else {
            throw ScreenshotRequestError(code: "add-entry-invalid", detail: "Add-entry sample name is empty.")
        }
        guard form.categoryIDs == ScreenshotFixture.addEntryCategoryIDs(for: request.localeIdentifier), !form.categoryIDs.isEmpty else {
            throw ScreenshotRequestError(code: "add-entry-invalid", detail: "Add-entry sample categories are missing.")
        }
        guard !form.notes.isEmpty else {
            throw ScreenshotRequestError(code: "add-entry-invalid", detail: "Add-entry sample notes are empty.")
        }
        guard form.isAddEnabled else {
            throw ScreenshotRequestError(code: "add-entry-invalid", detail: "Add-entry sample fails the Log Time validity gate.")
        }
    }
}

/// The capture Add-entry sheet: genuine Log Time UI over the History
/// viewport. The sheet never dismisses during capture (constant binding at
/// the call site); the container arrives via the environment.
struct ScreenshotAddEntrySheet: View {
    @EnvironmentObject var container: AppContainer
    let clock: AppClock
    let localeIdentifier: String

    var body: some View {
        let interval = ScreenshotFixture.addEntryInterval(
            calendar: clock.calendar,
            referenceDate: clock.now()
        )
        LogTimeView(
            service: container.timerService,
            initialText: ScreenshotFixture.addEntryText(for: localeIdentifier),
            initialCategoryIDs: ScreenshotFixture.addEntryCategoryIDs(for: localeIdentifier),
            initialNotes: ScreenshotFixture.addEntryNotes(for: localeIdentifier),
            initialInterval: interval
        )
        .environmentObject(container)
    }
}
#endif
