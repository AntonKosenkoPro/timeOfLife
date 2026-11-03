#if SCREENSHOT_CAPTURE
import SwiftUI

/// Add-entry frame support (screenshot-capture spec): the genuine Log Time
/// sheet prefilled with the fixture sample (all five cards — Name, Start,
/// End, Categories, Notes — with a visible notes value). Draft-only: the
/// sample is never saved, so the 55-entry committed totals stay identical.
/// Gated: absent from shipping builds.
@MainActor
enum ScreenshotAddEntry {
    /// Builds the sheet's form through the initializer — the same direct
    /// assignment the UI uses (no picker setters: no minute floor, no
    /// `timesTouched` flip). Minute-exact fixture values pass through
    /// unchanged.
    static func makeForm(service: TimerService, request: ScreenshotCaptureRequest) throws -> LogTimeViewModel {
        let interval = try ScreenshotFixture.addEntryInterval(
            calendar: request.calendar,
            referenceDate: request.referenceDate
        )
        return LogTimeViewModel(
            service: service,
            initialText: ScreenshotFixture.addEntryText(for: request.localeIdentifier),
            initialCategoryIDs: ScreenshotFixture.addEntryCategoryIDs(for: request.localeIdentifier),
            initialNotes: ScreenshotFixture.addEntryNotes(for: request.localeIdentifier),
            initialInterval: (start: interval.start, end: interval.end),
            now: request.referenceDate,
            calendar: request.calendar
        )
    }

    /// Fails closed unless the sample satisfies the form's own validity
    /// gate — the spec's "validated state", never a mock drawing.
    static func validate(request: ScreenshotCaptureRequest, container: AppContainer) throws {
        let interval = try ScreenshotFixture.addEntryInterval(
            calendar: request.calendar,
            referenceDate: request.referenceDate
        )
        guard interval.end > interval.start else {
            throw ScreenshotRequestError(code: "add-entry-invalid", detail: "Add-entry sample interval is not positive.")
        }
        let form = try makeForm(service: container.timerService, request: request)
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
        // The same derivation validate() already ran before mount: a
        // failure there fails the run closed and this sheet never mounts,
        // so the fallback below is unreachable in practice. It exists so a
        // future calendar change degrades to a diagnostic, never a trap
        // (and never ships — Screenshot configuration only).
        if let interval = try? ScreenshotFixture.addEntryInterval(
            calendar: clock.calendar,
            referenceDate: clock.now()
        ) {
            LogTimeView(
                service: container.timerService,
                initialText: ScreenshotFixture.addEntryText(for: localeIdentifier),
                initialCategoryIDs: ScreenshotFixture.addEntryCategoryIDs(for: localeIdentifier),
                initialNotes: ScreenshotFixture.addEntryNotes(for: localeIdentifier),
                initialInterval: interval,
                now: clock.now(),
                calendar: clock.calendar
            )
            .environmentObject(container)
        } else {
            Text("Screenshot capture unavailable")
                .font(.headline)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.backgroundPrimary.ignoresSafeArea())
        }
    }
}
#endif
