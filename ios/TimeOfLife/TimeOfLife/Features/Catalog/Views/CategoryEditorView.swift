import SwiftUI

/// The shared Category Editor sheet (Design/SCREENS/CategoryEditor.md,
/// category-management D4): name field, catalog icon grid, field validation,
/// Cancel, and a keyboard-safe pinned Save bar. Create mode starts with an
/// empty name and the default `tag` icon; edit mode prefills from the
/// passed-in category.
struct CategoryEditorView: View {
    @StateObject private var vm: CategoryEditorViewModel
    @Environment(\.dismiss)
    private var dismiss
    @FocusState private var isNameFocused: Bool

    init(
        store: LocalStore,
        category: Category?,
        onSaved: @escaping (Category) -> Void,
        onDuplicate: @escaping (Category) -> Void
    ) {
        _vm = StateObject(wrappedValue: CategoryEditorViewModel(
            store: store,
            category: category,
            onSaved: onSaved,
            onDuplicate: onDuplicate
        ))
    }

    var body: some View {
        EditorSheetScaffold(
            title: vm.isCreateMode ? L10n.categoryEditorCreateTitle.text : L10n.categoryEditorEditTitle.text,
            cancelTitle: L10n.categoryEditorCancel.text,
            isLoading: vm.isLoading,
            cancelAccessibilityId: "CategoryEditorCancelButton",
            usesMediumDetent: true,
            onCancel: { dismiss() },
            content: {
                TextFieldWithError(
                    title: L10n.categoryEditorNameLabel.text,
                    placeholder: L10n.categoryEditorNamePlaceholder.text,
                    text: $vm.name,
                    error: vm.fieldErrors.name,
                    keyboardType: .default,
                    textContentType: nil,
                    submitLabel: .done,
                    autocapitalization: .sentences,
                    accessibilityId: "CategoryEditorNameField"
                ) {
                    isNameFocused = false
                }
                .focused($isNameFocused)
                .onChange(of: vm.name) { _ in
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
            },
            bottomBar: {
                PrimaryButton(
                    title: L10n.categoryEditorSave.text,
                    icon: nil,
                    isLoading: vm.isLoading,
                    isDisabled: !vm.canSave,
                    accessibilityId: "CategoryEditorSaveButton"
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
        // Dismiss only after a successful save. Duplicate and stale
        // outcomes keep the editor open with actionable context.
        .onChange(of: vm.isSavedOrDuplicate) { saved in
            if saved {
                dismiss()
            }
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
