import SwiftUI

/// The shared Category Editor sheet (Design/SCREENS/CategoryEditor.md,
/// category-management D4): full-height sheet with Log Time toolbar chrome
/// (X dismiss, checkmark save), compact name field, catalog icon grid, and
/// field validation. Create mode starts with an empty name and the default
/// `tag` icon; edit mode prefills from the passed-in category.
struct CategoryEditorView: View {
    @StateObject private var vm: CategoryEditorViewModel
    @Environment(\.dismiss)
    private var dismiss
    @FocusState private var isNameFocused: Bool
    /// Drives the delete confirmation alert (edit mode).
    @State private var isShowingDeleteConfirm = false
    /// Called after a confirmed deletion so the presenter can reload.
    private let onDeleted: (() -> Void)?

    init(
        store: LocalStore,
        category: Category?,
        onSaved: @escaping (Category) -> Void,
        onDuplicate: @escaping (Category) -> Void,
        onDeleted: (() -> Void)? = nil
    ) {
        _vm = StateObject(wrappedValue: CategoryEditorViewModel(
            store: store,
            category: category,
            onSaved: onSaved,
            onDuplicate: onDuplicate
        ))
        self.onDeleted = onDeleted
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingLarge) {
                    TextFieldWithError(
                        title: L10n.categoryEditorNameLabel.text,
                        placeholder: L10n.categoryEditorNamePlaceholder.text,
                        text: $vm.name,
                        error: vm.fieldErrors.name,
                        keyboardType: .default,
                        textContentType: nil,
                        submitLabel: .done,
                        autocapitalization: .sentences,
                        accessibilityId: "CategoryEditorNameField",
                        onSubmit: { isNameFocused = false },
                        focused: $isNameFocused,
                        showClear: ClearButtonVisibility.shouldShow(
                            isFocused: isNameFocused,
                            text: vm.name
                        ),
                        onClear: { vm.name = "" },
                        clearAccessibilityId: "CategoryNameClearButton",
                        clearAccessibilityLabel: L10n.nameClear.text
                    )
                    .onChange(of: vm.name) {
                        vm.nameDidChange()
                    }

                    VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                        Text(L10n.categoryEditorIconLabel.text)
                            .font(.title2.bold())
                            .foregroundStyle(Theme.textPrimary)
                            .accessibilityAddTraits(.isHeader)

                        IconPickerGrid(
                            options: iconOptions,
                            selection: Binding(
                                get: { vm.icon.rawValue },
                                set: { vm.icon = CatalogIcon(validated: $0) }
                            ),
                            accessibilityId: "CategoryEditorIcon"
                        )
                    }

                    if let errorMessage = vm.errorMessage {
                        ErrorBanner(
                            message: errorMessage,
                            accessibilityId: "CategoryEditorErrorBanner"
                        )
                    }

                    if !vm.isCreateMode {
                        deleteSection
                    }
                }
                .padding(.horizontal, Theme.screenHorizontalPadding)
                .padding(.vertical, Theme.spacingMedium)
                .frame(maxWidth: Theme.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.backgroundPrimary)
            .navigationTitle(vm.isCreateMode ? L10n.categoryEditorCreateTitle.text : L10n.categoryEditorEditTitle.text)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Calendar grammar (Log Time parity): X dismisses, checkmark
                // saves. The checkmark mirrors the old Save bar's gate.
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .disabled(vm.isLoading)
                    .accessibilityLabel(L10n.categoryEditorDismissLabel.text)
                    .accessibilityIdentifier("CategoryEditorCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        vm.save()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!vm.canSave)
                    .accessibilityLabel(L10n.categoryEditorConfirmSaveLabel.text)
                    .accessibilityIdentifier("CategoryEditorSaveButton")
                }
            }
            // Scroll-away dismisses the keyboard (native interactive behavior).
            .scrollDismissesKeyboard(.interactively)
        }
        .interactiveDismissDisabled(vm.isLoading)
        .task {
            // Autofocus waits out the sheet presentation (issue #82,
            // NamePicker precedent): focusing instantly fires the keyboard
            // mid-animation, and the keyboard-driven auto-scroll computes
            // against moving layout, landing the field partly out of
            // viewport. Cancelled automatically on dismiss.
            try? await Task.sleep(nanoseconds: Self.focusDelayNanoseconds)
            guard !Task.isCancelled else { return }
            isNameFocused = true
        }
        .alert(
            L10n.deleteCategoryTitle.text,
            isPresented: $isShowingDeleteConfirm
        ) {
            Button(L10n.deleteCategoryConfirm.text, role: .destructive) {
                Task { await deleteCategory() }
            }
            Button(L10n.categoryEditorCancel.text, role: .cancel) {}
        } message: {
            Text(String(format: L10n.deleteCategoryMessage.text, vm.name))
        }
        // Dismiss only after a successful save. Duplicate and stale
        // outcomes keep the editor open with actionable context.
        .onChange(of: vm.isSavedOrDuplicate) { _, saved in
            if saved {
                dismiss()
            }
        }
    }

    // MARK: - Delete

    /// Sheet-presentation settle before autofocus (see `.task` above).
    private static let focusDelayNanoseconds: UInt64 = 400_000_000

    /// Bottom-of-page destructive Delete (edit mode only). Mirrors the entry
    /// form's delete section.
    private var deleteSection: some View {
        Button(role: .destructive) {
            isShowingDeleteConfirm = true
        } label: {
            Text(L10n.categoryEditorDelete.text)
                .font(.headline)
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapArea)
                .contentShape(Rectangle())
        }
        .background(Theme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .accessibilityIdentifier("CategoryEditorDeleteButton")
    }

    /// Deletes the category into the durable undo buffer; notifies the
    /// presenter and dismisses on success. On failure the editor stays open
    /// with the error banner.
    private func deleteCategory() async {
        if await vm.deleteConfirmed() {
            onDeleted?()
            dismiss()
        }
    }

    /// Keeps a valid synchronized icon visible in the picker even when the
    /// current OS cannot render it. The cell displays the `tag` fallback while
    /// preserving the stored raw value until the user explicitly changes it.
    private var iconOptions: [String] {
        let selected = vm.icon.rawValue
        guard CatalogIcon.canRender(selected) || !CatalogIcon.allSymbols.contains(selected) else {
            return CatalogIcon.renderableSymbols + [selected]
        }
        return CatalogIcon.renderableSymbols
    }
}

#if DEBUG
#Preview("Category Editor — Create EN Light") {
    let container = AppContainer.production()
    CategoryEditorView(
        store: container.localStore,
        category: nil,
        onSaved: { _ in },
        onDuplicate: { _ in }
    )
    .environmentObject(container)
}

#Preview("Category Editor — Edit RU Dark") {
    let container = AppContainer.production()
    CategoryEditorView(
        store: container.localStore,
        category: TimeOfLife.Category(
            id: "preview", name: "Спорт", icon: "figure.run",
            createdAt: Date(), updatedAt: Date()
        ),
        onSaved: { _ in },
        onDuplicate: { _ in }
    )
    .environmentObject(container)
    .preferredColorScheme(.dark)
    .environment(\.locale, .init(identifier: "ru"))
}
#endif
