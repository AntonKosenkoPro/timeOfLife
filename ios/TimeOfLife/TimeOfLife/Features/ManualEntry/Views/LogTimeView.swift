import SwiftUI

/// The manual time-logging sheet (manual-entry spec) grown into the unified
/// entry form (entry-editor spec), styled on the iOS Calendar add-event form
/// and trimmed to three rows: Activity (title over value, opening the shared
/// searchable picker), Starts and Ends (date + time pills with inline
/// single-open pickers). Cancel/Add (CREATE) or Cancel/Save (EDIT) live in
/// the navigation bar; the confirm action is a validity gate — disabled until
/// an activity is chosen and End is strictly after Start. LOCKED mode (an
/// imported entry) shows the values read-only with Cancel only. EDIT and
/// LOCKED modes offer a bottom-of-page destructive Delete. A save failure
/// surfaces as a non-field error with the draft intact and the form open.
struct LogTimeView: View {
    @StateObject private var vm: LogTimeViewModel
    @Environment(\.dismiss)
    private var dismiss
    /// The currently expanded inline picker, if any (Calendar behavior:
    /// one open at a time; tapping the active pill collapses it).
    @State private var expandedPicker: InlinePicker?
    /// Drives the delete confirmation alert (EDIT + LOCKED modes).
    @State private var isShowingDeleteConfirm = false
    /// Called after a successful save so the presenter can refresh.
    let onSaved: (() -> Void)?

    private enum InlinePicker {
        case startDate, startTime, endDate, endTime
    }

    init(
        service: TimerService,
        initialActivity: Activity? = nil,
        editing entry: TimeEntry? = nil,
        onSaved: (() -> Void)? = nil
    ) {
        _vm = StateObject(wrappedValue: LogTimeViewModel(
            service: service,
            initialActivity: initialActivity,
            editing: entry
        ))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.spacingMedium) {
                    activityCard
                        .disabled(vm.isLocked)
                        .opacity(vm.isLocked ? 0.6 : 1)
                    startsEndsCard
                        .disabled(vm.isLocked)
                        .opacity(vm.isLocked ? 0.6 : 1)
                    if vm.isLocked {
                        lockedNote
                    }
                    if vm.errorMessage != nil {
                        errorSection
                    }
                    if vm.mode != .create {
                        deleteSection
                    }
                }
                .padding(.horizontal, Theme.spacingMedium)
                .padding(.vertical, Theme.spacingMedium)
            }
            .background(Theme.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(formTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.logTimeCancel.text) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !vm.isLocked {
                        Button(vm.mode == .edit ? L10n.entrySave.text : L10n.logTimeAdd.text) {
                            Task { await save() }
                        }
                        .disabled(!vm.isAddEnabled)
                        .accessibilityIdentifier(vm.mode == .edit ? "EntryEditSaveButton" : "LogTimeAddButton")
                    }
                }
            }
            .alert(
                L10n.entryDeleteTitle.text,
                isPresented: $isShowingDeleteConfirm
            ) {
                Button(L10n.entryDeleteConfirm.text, role: .destructive) {
                    Task { await deleteEntry() }
                }
                Button(L10n.logTimeCancel.text, role: .cancel) {}
            } message: {
                Text(L10n.entryDeleteMessage.text)
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: pickerPresentation, onDismiss: vm.cancelSearch) {
            ActivitySearchSheet(vm: vm)
        }
    }

    /// Mode-specific navigation title (localized).
    private var formTitle: String {
        switch vm.mode {
        case .create: L10n.logTimeTitle.text
        case .edit: L10n.entryEditTitle.text
        case .locked: L10n.entryLockedTitle.text
        }
    }

    private var pickerPresentation: Binding<Bool> {
        Binding(
            get: { vm.isPickerActive },
            set: { if !$0 { vm.cancelSearch() } }
        )
    }

    private func save() async {
        if await vm.save() {
            onSaved?()
            dismiss()
        }
    }

    /// Deletes the entry into the durable undo buffer; dismisses on success
    /// (the presenter reloads via the cover/sheet dismissal). On failure the
    /// form stays open with the error banner.
    private func deleteEntry() async {
        if await vm.deleteConfirmed() {
            dismiss()
        }
    }

    // MARK: - Locked provenance note

    /// Read-only note for imported entries (LOCKED mode): bare source name
    /// plus why editing is disabled.
    private var lockedNote: some View {
        HStack(spacing: Theme.spacingExtraSmall) {
            Image(systemName: ActivityEntryRow.provenanceIcon)
            Text(String(
                format: L10n.entryLockedNote.text,
                locale: .current,
                EntryProvenance.name(for: vm.editingEntry?.source ?? "manual")
            ))
        }
        .font(.caption)
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacingMedium)
        .background(Theme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .accessibilityIdentifier("EntryLockedNote")
    }

    // MARK: - Delete

    /// Bottom-of-page destructive Delete (EDIT + LOCKED modes only).
    private var deleteSection: some View {
        Button(role: .destructive) {
            isShowingDeleteConfirm = true
        } label: {
            Text(L10n.entryDelete.text)
                .font(.headline)
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapArea)
                .contentShape(Rectangle())
        }
        .background(Theme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .accessibilityIdentifier("EntryDeleteButton")
    }

    // MARK: - Activity row

    private var activityCard: some View {
        Button {
            vm.activateSearch()
        } label: {
            VStack(alignment: .leading, spacing: Theme.spacingExtraSmall) {
                Text(L10n.logTimeActivity.text)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                HStack {
                    Text(vm.selectedActivity?.name ?? L10n.logTimeChooseActivity.text)
                        .foregroundStyle(vm.selectedActivity == nil ? Theme.textSecondary : Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: Theme.minTapArea)
            }
            .padding(Theme.spacingMedium)
            .contentShape(Rectangle())
        }
        .background(Theme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .accessibilityIdentifier("LogTimeActivityRow")
    }

    // MARK: - Starts / Ends rows

    private var startsEndsCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            timeRow(
                title: L10n.logTimeStarts.text,
                date: vm.startsAt,
                datePicker: .startDate,
                timePicker: .startTime,
                dateId: "LogTimeStartDatePill",
                timeId: "LogTimeStartTimePill"
            )
            Divider()
            timeRow(
                title: L10n.logTimeEnds.text,
                date: vm.endsAt,
                datePicker: .endDate,
                timePicker: .endTime,
                dateId: "LogTimeEndDatePill",
                timeId: "LogTimeEndTimePill"
            )
        }
        .padding(Theme.spacingMedium)
        .background(Theme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private func timeRow(
        title: String,
        date: Date,
        datePicker: InlinePicker,
        timePicker: InlinePicker,
        dateId: String,
        timeId: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingExtraSmall) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.spacingSmall) {
                pill(Self.dateText(for: date), active: expandedPicker == datePicker, id: dateId) {
                    toggle(datePicker)
                }
                pill(HistoryViewModel.timeText(for: date), active: expandedPicker == timePicker, id: timeId) {
                    toggle(timePicker)
                }
            }
            // Pills must switch highlight instantly — otherwise the capsule
            // background lags behind the text when the picker change animates.
            .animation(.none, value: expandedPicker)
            VStack(spacing: 0) {
                if expandedPicker == datePicker {
                    DatePicker(
                        "",
                        selection: dateBinding(for: datePicker),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .transition(.opacity)
                }
                if expandedPicker == timePicker {
                    DatePicker(
                        "",
                        selection: dateBinding(for: timePicker),
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .transition(.opacity)
                }
            }
            // Only the picker container animates; pills above stay instant.
            .animation(.easeInOut(duration: 0.2), value: expandedPicker)
            .clipped()
        }
    }

    private func pill(_ text: String, active: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.callout)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, Theme.spacingSmall + 4)
                .padding(.vertical, Theme.spacingSmall - 2)
                .foregroundStyle(active ? Theme.accentPrimary : Theme.textPrimary)
                .background(active ? Theme.color(Theme.accentPrimary, alpha: 0.15) : Theme.backgroundPrimary)
                .clipShape(Capsule())
        }
        .accessibilityIdentifier(id)
        // Belt-and-braces: never animate the highlight itself, even if a
        // parent transaction carries an animation.
        .transaction { $0.disablesAnimations = true }
    }

    private func toggle(_ picker: InlinePicker) {
        expandedPicker = (expandedPicker == picker) ? nil : picker
    }

    private func dateBinding(for picker: InlinePicker) -> Binding<Date> {
        Binding(
            get: {
                switch picker {
                case .startDate, .startTime: vm.startsAt
                case .endDate, .endTime: vm.endsAt
                }
            },
            set: {
                switch picker {
                case .startDate, .startTime: vm.setStartsAt($0)
                case .endDate, .endTime: vm.setEndsAt($0)
                }
            }
        )
    }

    // MARK: - Error

    private var errorSection: some View {
        Group {
            if let errorMessage = vm.errorMessage {
                ErrorBanner(
                    message: errorMessage,
                    accessibilityId: "LogTimeErrorBanner"
                )
            }
        }
    }

    // MARK: - Formatting

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static func dateText(for date: Date) -> String {
        dateFormatter.string(from: date)
    }
}

#if DEBUG
#Preview("Log Time — Empty") {
    let container = AppContainer.production()
    LogTimeView(service: container.timerService)
        .environmentObject(container)
}

#Preview("Log Time — RU locale") {
    let container = AppContainer.production()
    LogTimeView(service: container.timerService)
        .environment(\.locale, .init(identifier: "ru"))
        .environmentObject(container)
}
#endif
