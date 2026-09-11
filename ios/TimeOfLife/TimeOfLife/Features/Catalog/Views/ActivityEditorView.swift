import SwiftUI

/// The shared Activity Editor sheet (Design/SCREENS/ActivityEditor.md),
/// edit mode (refine-selected-activity-from-track change, design decision 3):
/// name, optional notes, optional Categories, field validation, and a pinned
/// Save bar. Saving is local-first via the atomic `LocalStore.refineActivity`
/// operation; the caller replaces the associated Activity in the current
/// TrackState without transitioning it.
struct ActivityEditorView: View {
    @StateObject private var vm: ActivityEditorViewModel
    @Environment(\.dismiss)
    private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var isShowingCategoryEditor = false
    /// Drives the delete confirmation alert.
    @State private var isShowingDeleteConfirm = false
    /// Called after a confirmed deletion so the presenter can settle
    /// (Track clears its selection; the detail sheet reloads and dismisses).
    private let onDeleted: (() -> Void)?

    init(
        store: LocalStore,
        activity: Activity,
        onSaved: @escaping (Activity) -> Void,
        onCollision: @escaping (Activity) -> Void,
        onDeleted: (() -> Void)? = nil
    ) {
        _vm = StateObject(wrappedValue: ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: onSaved,
            onCollision: onCollision
        ))
        self.onDeleted = onDeleted
    }

    var body: some View {
        EditorSheetScaffold(
            title: L10n.activityEditorEditTitle.text,
            cancelTitle: L10n.activityEditorCancel.text,
            isLoading: vm.isLoading,
            cancelAccessibilityId: "ActivityEditorCancelButton",
            usesMediumDetent: false,
            onCancel: { dismiss() },
            content: {
                TextFieldWithError(
                    title: L10n.activityEditorNameLabel.text,
                    placeholder: L10n.activityEditorNamePlaceholder.text,
                    text: $vm.name,
                    error: vm.fieldErrors.name,
                    keyboardType: .default,
                    textContentType: nil,
                    submitLabel: .done,
                    autocapitalization: .sentences,
                    accessibilityId: "ActivityEditorNameField"
                ) {
                    isNameFocused = false
                }
                .focused($isNameFocused)
                .onChange(of: vm.name) { _ in
                    vm.nameDidChange()
                }

                notesField

                categoriesSection

                if let errorMessage = vm.errorMessage {
                    ErrorBanner(
                        message: errorMessage,
                        accessibilityId: "ActivityEditorErrorBanner"
                    )
                }

                deleteSection
            },
            bottomBar: {
                PrimaryButton(
                    title: L10n.activityEditorSave.text,
                    icon: nil,
                    isLoading: vm.isLoading,
                    isDisabled: !vm.canSave,
                    accessibilityId: "ActivityEditorSaveButton"
                ) {
                    vm.save()
                }
                .padding(.horizontal, Theme.screenHorizontalPadding)
                .padding(.vertical, Theme.spacingSmall)
                .background(Theme.backgroundPrimary)
            }
        )
        .onAppear {
            isNameFocused = true
        }
        .alert(
            L10n.activityDeleteTitle.text,
            isPresented: $isShowingDeleteConfirm
        ) {
            Button(L10n.activityDeleteConfirm.text, role: .destructive) {
                Task { await deleteActivity() }
            }
            Button(L10n.activityEditorCancel.text, role: .cancel) {}
        } message: {
            Text(String(
                format: L10n.activityDeleteMessage.text,
                locale: .current,
                vm.originalName,
                vm.committedEntryCount,
                vm.committedTotalText
            ))
        }
        .sheet(isPresented: $isShowingCategoryEditor) {
            CategoryEditorView(
                store: vm.categoryStore,
                category: nil,
                onSaved: { category in
                    Task {
                        await vm.reloadCategories()
                        vm.selectCategory(category.id)
                    }
                },
                onDuplicate: { _ in
                    vm.errorMessage = L10n.errorCategoryExists.text
                }
            )
        }
    }

    // MARK: - Delete

    /// Bottom-of-page destructive Delete (edit mode; the Activity editor has
    /// no create mode). Mirrors the entry form's delete section.
    private var deleteSection: some View {
        Button(role: .destructive) {
            isShowingDeleteConfirm = true
        } label: {
            Text(L10n.activityEditorDelete.text)
                .font(.headline)
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapArea)
                .contentShape(Rectangle())
        }
        .background(Theme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .accessibilityIdentifier("ActivityEditorDeleteButton")
    }

    /// Deletes the activity into the durable undo buffer; notifies the
    /// presenter and dismisses on success (the presenter settles via
    /// `onDeleted` and the sheet dismissal). On failure the editor stays open
    /// with the error banner.
    private func deleteActivity() async {
        if await vm.deleteConfirmed() {
            onDeleted?()
            dismiss()
        }
    }

    // MARK: - Notes

    private var notesField: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text(L10n.activityEditorNotesLabel.text)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            TextEditor(text: $vm.notes)
                .frame(minHeight: 96)
                .padding(Theme.spacingSmall)
                .background(Theme.backgroundSecondary)
                .cornerRadius(Theme.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .stroke(vm.fieldErrors.notes != nil ? Theme.danger : Theme.hairline, lineWidth: 1)
                )
                .accessibilityIdentifier("ActivityEditorNotesField")
                .onChange(of: vm.notes) { _ in
                    vm.notesDidChange()
                }

            HStack {
                if let notesError = vm.fieldErrors.notes {
                    Text(notesError)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                        .accessibilityIdentifier("ActivityEditorNotesFieldError")
                }
                Spacer()
                Text(String(format: L10n.activityEditorNotesCounter.text, vm.notes.count))
                    .font(.caption)
                    .foregroundStyle(vm.notes.count > ActivityEditorViewModel.notesMaxLength
                                     ? Theme.danger
                                     : Theme.textSecondary)
            }
        }
    }

    // MARK: - Categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text(L10n.activityEditorTagsLabel.text)
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)

            if vm.availableCategories.isEmpty {
                VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                    Text(L10n.activityEditorNoTags.text)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Button(L10n.activityEditorAddCategory.text) {
                        isShowingCategoryEditor = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentPrimary)
                    .frame(minHeight: Theme.minTapArea)
                    .accessibilityIdentifier("ActivityEditorAddCategoryButton")
                }
            } else {
                TagSelector(
                    options: vm.availableCategories,
                    selected: Set(vm.selectedCategoryIDs),
                    onToggle: { categoryID in
                        vm.toggleCategory(categoryID)
                    },
                    accessibilityId: "ActivityEditorTags"
                )
            }
        }
    }
}

#if DEBUG
#Preview("Activity Editor — EN Light") {
    let container = AppContainer.production()
    let activity = Activity(id: "preview-en", name: "Gym")
    ActivityEditorView(
        store: container.localStore,
        activity: activity,
        onSaved: { _ in },
        onCollision: { _ in }
    )
    .environmentObject(container)
}

#Preview("Activity Editor — RU Dark") {
    let container = AppContainer.production()
    let activity = Activity(id: "preview-ru", name: "Спортзал", notes: "Leg day")
    ActivityEditorView(
        store: container.localStore,
        activity: activity,
        onSaved: { _ in },
        onCollision: { _ in }
    )
    .environmentObject(container)
    .preferredColorScheme(.dark)
    .environment(\.locale, .init(identifier: "ru"))
}
#endif
