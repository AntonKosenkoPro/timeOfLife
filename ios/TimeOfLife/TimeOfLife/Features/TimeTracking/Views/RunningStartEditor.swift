import SwiftUI

/// Shared preset row: bidirectional minute steppers that move the wheel
/// from its current position (cumulative taps accumulate) without
/// applying. Back presets go earlier; forward presets go later, clamped
/// at now so the wheel never strands Done disabled. The user confirms with
/// Done, so presets and wheel share the single gated confirm path.
/// Accessibility labels use the system relative formatter for back presets
/// (free Russian plurals) and explicit localized strings for forward ones.
private struct StartPresetRow: View {
    let now: Date
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
                .foregroundStyle(Theme.textPrimary)
                .background(Theme.backgroundSecondary)
                .clipShape(Capsule())
        }
        .buttonStyle(PressablePillStyle())
        .frame(minHeight: 48)
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
        return minutes == 15 ? L10n.timerStartForward15.text : L10n.timerStartForward30.text
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

    var body: some View {
        Button {
            draft = nil
            // The wheel is time-only: seed the day from the current start so
            // a reopened sheet reflects where the run actually began.
            picksYesterday = RunningStartTimeResolver.isYesterday(startedAt, now: now)
            isPresented = true
        } label: {
            Text(startCaption)
                .font(.caption.weight(.semibold))
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
                    StartPresetRow(now: now) { minutes in
                        // Cumulative steppers: each tap moves the wheel
                        // another N minutes from its current position —
                        // back presets go earlier, forward presets go later
                        // clamped at the floored now (a start can never be
                        // in the future, so Done is never stranded disabled).
                        // The day follows the result (past midnight lands on
                        // Yesterday) so the wheel and the segment never
                        // disagree.
                        let base = min(draft ?? startedAt, now)
                        let target = RunningStartTimeResolver.floorToMinute(
                            min(base.addingTimeInterval(Double(minutes * 60)), now)
                        )
                        draft = target
                        picksYesterday = RunningStartTimeResolver.isYesterday(target, now: now)
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
                    .onChange(of: picksYesterday) {
                        // Switching back to Today with a future wheel time
                        // would strand Done disabled on a confusing wheel —
                        // snap to now instead (same LogTime philosophy as the
                        // range fallback below: the gate, not a clamp, is the
                        // enforcer, but the default view is never invalid).
                        let candidate = draft ?? startedAt
                        if !picksYesterday,
                           RunningStartTimeResolver.floorToMinute(candidate) > Date() {
                            draft = Date()
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
                        .accessibilityIdentifier("RunningStartApply")
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var startCaption: String {
        RunningStartTimeResolver.caption(
            for: startedAt,
            now: now,
            timeText: HistoryViewModel.timeText(for:)
        )
    }

    /// Selectable wheel range (LogTime `endTimeRange` grammar): Today is
    /// bounded by now (the wheel offers no future times); Yesterday is the
    /// whole prior day. The Done-disabled gate stays the enforcer for
    /// degenerate cases (e.g. a same-day selection stranded by the clock
    /// crossing midnight while the sheet is open), never a clamp.
    private var wheelRange: ClosedRange<Date> {
        let calendar = Calendar.current
        if picksYesterday {
            let day = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            let start = calendar.startOfDay(for: day)
            let end = (calendar.date(byAdding: .day, value: 1, to: start) ?? now)
                .addingTimeInterval(-1)
            return start...max(start, end)
        }
        let start = calendar.startOfDay(for: now)
        return start...max(start, now)
    }

    /// The wheel pick with the segmented day applied, floored to the minute.
    /// Nil while the pick is in the future (Today segment only — the spec
    /// gate: Done stays disabled, no error text). Yesterday is always in
    /// the past. The shared resolver's future-fold stays as a safety net
    /// behind `updateDraftStartedAt`, but the UI never relies on it.
    private var resolvedSelection: Date? {
        let calendar = Calendar.current
        let picked = draft ?? startedAt
        if picksYesterday {
            let day = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            let comps = calendar.dateComponents([.hour, .minute], from: picked)
            return calendar.date(
                bySettingHour: comps.hour ?? 0,
                minute: comps.minute ?? 0,
                second: 0,
                of: day
            )
        }
        let floored = RunningStartTimeResolver.floorToMinute(picked, calendar: calendar)
        return floored <= now ? floored : nil
    }
}
