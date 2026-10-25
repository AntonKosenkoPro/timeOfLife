import SwiftUI

/// Shared preset row: bidirectional minute steppers that move the wheel
/// from its current position (cumulative taps accumulate) without
/// applying. Back presets go earlier; forward presets go later, clamped
/// at now so the wheel never strands Done disabled. The row owns no clock:
/// the caller resolves the offset against its own reference time, so the
/// row stays a pure function of the tap. The user confirms with Done, so
/// presets and wheel share the single gated confirm path. Accessibility
/// labels use the system relative formatter for back presets (free Russian
/// plurals) and explicit localized strings for forward ones.
private struct StartPresetRow: View {
    let onPreset: (Int) -> Void

    var body: some View {
        HStack(spacing: Theme.spacingSmall) {
            ForEach(RunningStartTimeResolver.backPresetOffsetsMinutes, id: \.self) { minutes in
                presetButton(text: "−\(minutes)", minutes: -minutes)
            }
            Divider()
                .frame(height: 24)
                .background(Theme.hairline)
                .padding(.horizontal, Theme.spacingSmall)
                .accessibilityHidden(true)
            ForEach(RunningStartTimeResolver.forwardPresetOffsetsMinutes, id: \.self) { minutes in
                presetButton(text: "+\(minutes)", minutes: minutes)
            }
        }
    }

    private func presetButton(text: String, minutes: Int) -> some View {
        Button {
            onPreset(minutes)
        } label: {
            Text(text)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, Theme.spacingSmall + 4)
                .padding(.vertical, Theme.spacingSmall - 2)
                .frame(minHeight: 48)
                .contentShape(Capsule())
                .foregroundStyle(Theme.textPrimary)
                .background(Theme.backgroundSecondary)
                .clipShape(Capsule())
        }
        .buttonStyle(PressablePillStyle())
        .accessibilityLabel(Self.presetLabel(minutes: minutes))
    }

    private static func presetLabel(minutes: Int) -> String {
        if minutes < 0 {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(
                from: DateComponents(minute: minutes)
            )
        }
        switch minutes {
        case 15:
            return L10n.timerStartForward15.text
        case 30:
            return L10n.timerStartForward30.text
        default:
            // Future offsets fall back to the relative formatter so a new
            // preset never silently inherits a sibling's label.
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(
                from: DateComponents(minute: minutes)
            )
        }
    }
}

/// HIG press state for the custom capsule pills (HIG Buttons: a custom
/// button must show a press state, and hit regions must reach 44×44 pt —
/// the latter via `minHeight` at the call site).
private struct PressablePillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

/// The tappable `Started HH:MM` caption (editable-running-start-time): opens
/// a medium-detent sheet with presets, an optional wheel, and a checkmark
/// confirm. Nothing on Track moves — the editor is modal (D10-safe).
/// Presets position the wheel without applying; everything applies on Done
/// through the single gated confirm path. The validity gate
/// (`newStart <= now`) lives in `TrackViewModel.updateDraftStartedAt`;
/// overlap with existing entries is allowed (manual-entry precedent).
struct RunningStartEditor: View {
    let startedAt: Date
    let now: Date
    let onPick: (Date) -> Void

    @State private var isPresented = false
    @State private var draft: Date?
    @State private var picksYesterday = false
    /// The sheet's frozen reference clock, captured at open. The parent
    /// re-renders every elapsed-tick second, but the open sheet must not
    /// observe that: the wheel range, preset clamp, day snap, and gate all
    /// read this single value so nothing shifts under the user's finger.
    @State private var referenceNow = Date()

    var body: some View {
        Button {
            draft = nil
            // The wheel is time-only: seed the day from the current start so
            // a reopened sheet reflects where the run actually began, and
            // freeze the reference clock for this editing session.
            picksYesterday = RunningStartTimeResolver.isYesterday(startedAt, now: now)
            referenceNow = Date()
            isPresented = true
        } label: {
            Text(startCaption)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(minHeight: Theme.minTapArea)
                .contentShape(Rectangle())
                .foregroundStyle(Theme.accentPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("RunningStartCaption")
        .accessibilityHint(L10n.timerStartEditorTitle.text)
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                VStack(spacing: Theme.spacingMedium) {
                    Text(L10n.timerStartEditorTitle.text)
                        .font(.headline)
                    StartPresetRow { minutes in
                        // Cumulative steppers: each tap moves the wheel
                        // another N minutes from its current position —
                        // back presets go earlier, forward presets go later
                        // clamped at the floored reference now (a start can
                        // never be in the future, so Done is never stranded
                        // disabled). The day follows the result (past
                        // midnight lands on Yesterday) so the wheel and the
                        // segment never disagree.
                        let base = min(draft ?? startedAt, referenceNow)
                        let target = RunningStartTimeResolver.floorToMinute(
                            min(base.addingTimeInterval(Double(minutes * 60)), referenceNow)
                        )
                        draft = target
                        picksYesterday = RunningStartTimeResolver.isYesterday(target, now: referenceNow)
                    }
                    .accessibilityIdentifier("RunningStartPresets")
                    // Explicit day instead of a silent fold: Today rejects
                    // future wheel times (Done stays disabled — the spec
                    // gate); Yesterday is always in the past. A one-minute
                    // wheel nudge can never become a ~24h backdate by
                    // accident again.
                    Picker("", selection: $picksYesterday) {
                        Text(L10n.timerStartToday.text).tag(false)
                        Text(L10n.timerStartYesterday.text).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("RunningStartDayPicker")
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { draft ?? startedAt },
                            set: { draft = $0 }
                        ),
                        in: wheelRange,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(height: 216)
                    .accessibilityIdentifier("RunningStartWheel")
                    .onChange(of: picksYesterday) { _, newYesterday in
                        // Re-resolve under the NEW segment and materialize it:
                        // leaving a yesterday-based draft in place while the
                        // gate reads today would strand Done disabled on an
                        // out-of-range wheel, and a later preset would compute
                        // from the stale day and flip the segment back under
                        // the user. When the pick doesn't resolve (future
                        // time on Today), the draft stands and Done stays
                        // disabled — the spec gate, no silent clamp.
                        let candidate = draft ?? startedAt
                        if let valid = RunningStartTimeResolver.resolveForDay(
                            picked: candidate,
                            yesterday: newYesterday,
                            now: referenceNow
                        ) {
                            draft = valid
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Theme.backgroundPrimary.ignoresSafeArea())
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(Theme.backgroundPrimary, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            if let selection = resolvedSelection {
                                onPick(selection)
                            }
                            self.draft = nil
                            isPresented = false
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .disabled(resolvedSelection == nil)
                        .accessibilityLabel(L10n.timerStartConfirm.text)
                        .accessibilityIdentifier("RunningStartApply")
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var startCaption: String {
        RunningStartTimeResolver.caption(
            for: startedAt,
            now: now,
            timeText: HistoryViewModel.timeText(for:)
        )
    }

    /// Selectable wheel range (LogTime `endTimeRange` grammar), computed
    /// from the frozen reference clock so the bounds never shift under the
    /// user's finger: Today is bounded by the reference now (the wheel
    /// offers no future times); Yesterday is the whole prior day. The
    /// Done-disabled gate stays the enforcer for degenerate cases (e.g. a
    /// same-day selection stranded by the clock crossing midnight while the
    /// sheet is open), never a clamp.
    private var wheelRange: ClosedRange<Date> {
        let calendar = Calendar.current
        if picksYesterday {
            let day = calendar.date(byAdding: .day, value: -1, to: referenceNow) ?? referenceNow
            let start = calendar.startOfDay(for: day)
            let end = (calendar.date(byAdding: .day, value: 1, to: start) ?? referenceNow)
                .addingTimeInterval(-1)
            return start...max(start, end)
        }
        let start = calendar.startOfDay(for: referenceNow)
        return start...max(start, referenceNow)
    }

    /// The wheel pick with the segmented day applied (Today rebuilds the
    /// pick on today's date, so a yesterday-based draft can never leak
    /// through the gate). Nil while the pick is in the future (Today
    /// segment only — the spec gate: Done stays disabled, no error text).
    /// Yesterday always resolves. The shared resolver stays the single
    /// implementation; the UI never folds days on its own.
    private var resolvedSelection: Date? {
        RunningStartTimeResolver.resolveForDay(
            picked: draft ?? startedAt,
            yesterday: picksYesterday,
            now: referenceNow
        )
    }
}
