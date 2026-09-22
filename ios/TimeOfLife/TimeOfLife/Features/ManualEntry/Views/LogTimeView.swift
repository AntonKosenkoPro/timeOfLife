import SwiftUI

/// The unified entry form (entry-editor spec + manual-entry CREATE mode),
/// styled on the iOS Calendar add-event form and trimmed to four rows: Name,
/// Categories (shared ordered `TagSelector`), Notes, Starts and Ends (date +
/// time pills with inline single-open pickers). Cancel/Add (CREATE) or
/// Cancel/Save (EDIT) live in the navigation bar; the confirm action is a
/// validity gate — disabled until the trimmed name is non-empty and End is
/// strictly after Start. LOCKED mode shows the values read-only with Cancel
/// only; EDIT and LOCKED offer a bottom destructive Delete. A save failure
/// surfaces as a non-field error with the draft intact and the form open.
struct LogTimeView: View {
    @StateObject private var vm: LogTimeViewModel
    @EnvironmentObject var container: AppContainer
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
        initialText: String = "",
        initialCategoryIDs: [String] = [],
        editing entry: TimeEntry? = nil,
        onSaved: (() -> Void)? = nil
    ) {
        _vm = StateObject(wrappedValue: LogTimeViewModel(
            service: service,
            initialText: initialText,
            initialCategoryIDs: initialCategoryIDs,
            editing: entry
        ))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.spacingMedium) {
                    nameCard
                        .disabled(vm.isLocked)
                        .opacity(vm.isLocked ? 0.6 : 1)
                    categoriesCard
                        .disabled(vm.isLocked)
                        .opacity(vm.isLocked ? 0.6 : 1)
                    notesCard
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
            .task {
                await vm.loadCategoriesIfNeeded(store: container.localStore)
            }
        }
        .navigationViewStyle(.stack)
    }

    /// Mode-specific navigation title (localized).
    private var formTitle: String {
        switch vm.mode {
        case .create: L10n.logTimeTitle.text
        case .edit: L10n.entryEditTitle.text
        case .locked: L10n.entryLockedTitle.text
        }
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

    // MARK: - Name row

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacingExtraSmall) {
            Text(L10n.entryNameLabel.text)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            TextField(L10n.entryNamePlaceholder.text, text: $vm.name)
                .submitLabel(.done)
                .font(.body)
                .frame(minHeight: Theme.minTapArea)
        }
        .padding(Theme.spacingMedium)
        .background(Theme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .accessibilityIdentifier("EntryNameRow")
    }

    // MARK: - Categories row

    private var categoriesCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacingExtraSmall) {
            Text(L10n.entryCategoriesLabel.text)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            TagSelector(
                options: vm.availableCategories,
                selected: Set(vm.categoryIDs),
                onToggle: { vm.toggleCategory($0) },
                accessibilityId: "EntryCategories"
            )
        }
        .padding(Theme.spacingMedium)
        .background(Theme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .accessibilityIdentifier("EntryCategoriesRow")
    }

    // MARK: - Notes row

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacingExtraSmall) {
            Text(L10n.entryNotesLabel.text)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            TextField(L10n.entryNotesPlaceholder.text, text: $vm.notes)
                .submitLabel(.done)
                .font(.body)
                .frame(minHeight: Theme.minTapArea)
        }
        .padding(Theme.spacingMedium)
        .background(Theme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .accessibilityIdentifier("EntryNotesRow")
    }

    // MARK: - Locked provenance note

    /// Read-only note for imported entries (LOCKED mode): bare source name
    /// plus why editing is disabled.
    private var lockedNote: some View {
        HStack(spacing: Theme.spacingExtraSmall) {
            Image(systemName: "arrow.triangle.2.circlepath")
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
                    GeometryReader { proxy in
                        DatePicker(
                            "",
                            selection: dateBinding(for: datePicker),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .frame(width: proxy.size.width)
                    }
                    .frame(height: Self.graphicalPickerHeight)
                    .transition(.opacity)
                }
                if expandedPicker == timePicker {
                    GeometryReader { proxy in
                        DatePicker(
                            "",
                            selection: dateBinding(for: timePicker),
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(width: proxy.size.width)
                    }
                    .frame(height: Self.wheelPickerHeight)
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

    /// Fixed wheel-picker height (standard `UIPickerView` height): the
    /// GeometryReader container needs an explicit height.
    private static let wheelPickerHeight: CGFloat = 216
    /// Fixed calendar-picker height: large enough for six-week months on
    /// iOS 15 without clipping.
    private static let graphicalPickerHeight: CGFloat = 360

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
#endif
