import SwiftUI

/// The task editor sheet (day-planner 14.1/15.1/16.3): edits one planner
/// task's name, ordered category set, and notes — the manual entry form
/// with the Start and End cards omitted (same shared Name entry card into
/// `NamePicker`, same Categories card, same Notes presenter, same order,
/// same validation, same save gate). Categories and notes are optional
/// (zero tags and empty notes allowed, tag order preserved); identical
/// names stay separate identities. Tapping a planner row is the only entry
/// point. A save failure surfaces as a non-field error with the draft
/// intact and the sheet open.
struct PlannerTaskEditorSheet: View {
    @ObservedObject var vm: PlannerViewModel
    @EnvironmentObject var container: AppContainer
    @Environment(\.dismiss)
    private var dismiss
    /// Pushes the inline category editor (inline-category-creation): on the
    /// sheet's internal stack, so no sheet ever stacks over this sheet
    /// (Log Time CREATE-sheet precedent).
    @State private var isShowingCategoryEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.spacingMedium) {
                    nameCard
                    categoriesCard
                    notesCard
                    if vm.errorMessage != nil {
                        errorSection
                    }
                }
                .padding(.horizontal, Theme.spacingMedium)
                .padding(.vertical, Theme.spacingMedium)
            }
            .background(Theme.backgroundPrimary.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L10n.plannerEditorTitle.text)
                        .font(.headline)
                        .lineLimit(1)
                }
                // Calendar grammar (fix-50-nav-buttons): X cancels, the
                // checkmark saves through the validity gate.
                EditorToolbar(
                    showsDismiss: true,
                    dismissAccessibilityLabel: L10n.entryDismissLabel.text,
                    dismissAccessibilityId: "PlannerEditorDismissButton",
                    isDismissDisabled: false,
                    onDismiss: dismiss(),
                    showsConfirm: true,
                    confirmAccessibilityLabel: L10n.plannerSave.text,
                    confirmAccessibilityId: "PlannerEditorSaveButton",
                    isConfirmDisabled: !vm.isSheetSaveEnabled
                ) {
                    Task {
                        if await vm.saveSheet() { dismiss() }
                    }
                }
            }
            .task {
                await vm.loadSheetCategoriesIfNeeded()
                await vm.loadSheetNameRecentsIfNeeded()
            }
            .navigationDestination(isPresented: $isShowingCategoryEditor) {
                CategoryEditorForm(
                    store: container.localStore,
                    category: nil,
                    onSaved: { category in
                        Task { await vm.attachSheetCategory(category) }
                    },
                    onDuplicate: { _ in },
                    showsDismiss: false
                )
            }
        }
    }

    /// The Name card (day-planner 16.3): the shared `EntryNameCard` — the
    /// same push row into `NamePicker` the Log Time form uses (same
    /// behavior, same chrome, one component never a copy). The picker's
    /// completion writes the sheet drafts (`applySheetSuggestion` fills the
    /// exact text plus the entry's ordered categories;
    /// `completeSheetTypedName` resolves typed text the same way); Back
    /// discards the picker typing (copy-on-open, manual-form cancel
    /// semantics).
    private var nameCard: some View {
        EntryNameCard(
            value: vm.sheetName,
            placeholder: L10n.entryNamePlaceholder.text,
            recents: vm.sheetNameRecents,
            categories: Dictionary(uniqueKeysWithValues: vm.availableCategories.map { ($0.id, $0) }),
            emptyHint: L10n.timerRecentsEmptyHint.text,
            accessibilityID: "PlannerEditorNameRow",
            onCompleteSuggestion: {
                vm.applySheetSuggestion(text: $0.text, categoryIDs: $0.categoryIDs)
            },
            onCompleteText: { vm.completeSheetTypedName($0) }
        )
    }

    /// The Categories card (Log Time categories-card grammar): the shared
    /// ordered `TagSelector` with the inline-creation chip, at natural
    /// height inside the outer form scroll (no internal scrolling). The
    /// tap-away resign is a no-op: the sheet holds no inline field (Name
    /// entry lives on the pushed picker page, like the Log Time form).
    private var categoriesCard: some View {
        FormCard(accessibilityID: "PlannerEditorCategoriesRow", resignFocus: ()) {
            VStack(alignment: .leading, spacing: Theme.spacingExtraSmall) {
                Text(L10n.entryCategoriesLabel.text)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                TagSelector(
                    options: vm.availableCategories,
                    selected: vm.sheetCategoryIDs,
                    onToggle: {
                        vm.toggleSheetCategory($0)
                    },
                    onCreate: { isShowingCategoryEditor = true },
                    accessibilityId: "PlannerEditorCategories",
                    isScrollable: false
                )
            }
        }
    }

    /// The Notes card (Log Time notes-card grammar): a presenter row — a
    /// caption plus a trailing chevron over the full-width 1–5 line
    /// preview (placeholder when empty) — that pushes the shared
    /// `NotesEditorPage` (copy-on-open: X discards, ✓ writes
    /// `vm.sheetNotes` only and the validity gate re-evaluates).
    /// Full-card push, mirroring the Name card: the link owns the padded
    /// chrome so caption, chevron, preview, blank, and padding all push.
    /// No FormCard tap-away here — it would consume those taps (Log Time
    /// notes-presenter precedent).
    private var notesCard: some View {
        NavigationLink {
            NotesEditorPage(initialText: vm.sheetNotes, entryName: vm.sheetName) { vm.sheetNotes = $0 }
        } label: {
            VStack(alignment: .leading, spacing: Theme.spacingExtraSmall) {
                HStack(spacing: Theme.spacingSmall) {
                    Text(L10n.entryNotesLabel.text)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
                Text(vm.sheetNotes.isEmpty ? L10n.entryNotesPlaceholder.text : vm.sheetNotes)
                    .font(.body)
                    .lineLimit(1...5)
                    .foregroundStyle(vm.sheetNotes.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapArea, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.spacingMedium)
            .background(Theme.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.entryNotesLabel.text)
        .accessibilityValue(vm.sheetNotes.isEmpty ? L10n.entryNotesPlaceholder.text : vm.sheetNotes)
        .accessibilityIdentifier("PlannerEditorNotesRow")
    }

    private var errorSection: some View {
        Group {
            if let errorMessage = vm.errorMessage {
                ErrorBanner(
                    message: errorMessage,
                    accessibilityId: "PlannerEditorErrorBanner"
                )
            }
        }
    }
}
