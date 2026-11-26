import SwiftUI

/// The task editor sheet (day-planner 14.1): edits one planner task's name
/// and ordered category set in Log Time sheet grammar — the same field
/// order (Name, then Categories), the same card chrome (`FormCard`), the
/// same validity gate (Save disabled until the trimmed name satisfies the
/// shared timer-name rule), and the same inline category creation —
/// reduced to those two fields. Categories are optional (zero allowed,
/// order preserved); identical names stay separate identities. Tapping a
/// planner row is the only entry point. A save failure surfaces as a
/// non-field error with the draft intact and the sheet open.
struct PlannerTaskEditorSheet: View {
    @ObservedObject var vm: PlannerViewModel
    @EnvironmentObject var container: AppContainer
    @Environment(\.dismiss)
    private var dismiss
    /// Pushes the inline category editor (inline-category-creation): on the
    /// sheet's internal stack, so no sheet ever stacks over this sheet
    /// (Log Time CREATE-sheet precedent).
    @State private var isShowingCategoryEditor = false
    /// The text field holding focus, if any (tap-away/scroll-away resigns it).
    @FocusState private var focusedField: SheetField?

    /// The sheet's focusable field (tap-away/scroll-away dismissal target).
    private enum SheetField {
        case name
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.spacingMedium) {
                    nameCard
                    categoriesCard
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

    /// The Name card (Log Time name-card grammar: caption over the value):
    /// an inline field bound to the sheet draft, prefilled from the task.
    private var nameCard: some View {
        FormCard(accessibilityID: "PlannerEditorNameRow", resignFocus: focusedField = nil) {
            VStack(alignment: .leading, spacing: Theme.spacingExtraSmall) {
                Text(L10n.entryNameLabel.text)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                TextField(L10n.entryNamePlaceholder.text, text: $vm.sheetName)
                    .focused($focusedField, equals: .name)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapArea, alignment: .leading)
                    .accessibilityLabel(L10n.entryNameLabel.text)
                    .accessibilityIdentifier("PlannerEditorNameField")
            }
        }
    }

    /// The Categories card (Log Time categories-card grammar): the shared
    /// ordered `TagSelector` with the inline-creation chip, at natural
    /// height inside the outer form scroll (no internal scrolling).
    private var categoriesCard: some View {
        FormCard(accessibilityID: "PlannerEditorCategoriesRow", resignFocus: focusedField = nil) {
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
                        // The plain card tap-away stays silent on chip taps
                        // (consumed), so toggles resign explicitly here
                        // (Log Time categories-card grammar).
                        focusedField = nil
                    },
                    onCreate: { isShowingCategoryEditor = true },
                    accessibilityId: "PlannerEditorCategories",
                    isScrollable: false
                )
            }
        }
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
