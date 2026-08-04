import SwiftUI

/// Category Editor sheet (F2/U1/U2). Shared create/edit sheet.
struct CategoryEditorView: View {
    @StateObject var vm: CategoryEditorViewModel
    @Environment(\.dismiss)
    private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var bottomBarHeight: CGFloat = 0

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.spacingLarge) {
                    Text(vm.editingCategory != nil
                        ? L10n.categoryEditorEditTitle.text
                        : L10n.categoryEditorCreateTitle.text)
                        .font(.title.bold())
                        .foregroundStyle(Theme.textPrimary)

                    TextFieldWithError(
                        title: L10n.categoryEditorNameLabel.text,
                        placeholder: L10n.categoryEditorNamePlaceholder.text,
                        text: $vm.name,
                        error: vm.fieldError,
                        keyboardType: .default,
                        textContentType: nil,
                        submitLabel: .done,
                        autocapitalization: .sentences,
                        accessibilityId: "CategoryEditorNameField"
                    ) {
                        isNameFocused = false
                        Task { await save() }
                    }
                    .focused($isNameFocused)

                    SectionHeader(title: L10n.categoryEditorIconLabel.text)
                    IconPickerGrid(
                        options: CatalogIcon.allowedSymbols,
                        selection: $vm.icon,
                        accessibilityId: "CategoryEditorIcon")

                    if let errorMessage = vm.errorMessage {
                        ErrorBanner(message: errorMessage, accessibilityId: "CategoryEditorErrorBanner")
                    }

                    Color.clear.frame(height: bottomBarHeight + Theme.spacingLarge)
                }
                .padding(.horizontal, Theme.screenHorizontalPadding)
                .padding(.top, Theme.spacingLarge)
                .frame(maxWidth: Theme.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(vm.editingCategory != nil
                ? L10n.categoryEditorEditTitle.text
                : L10n.categoryEditorCreateTitle.text)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.categoryEditorCancel.text) {
                        dismiss()
                    }
                    .accessibilityIdentifier("CategoryEditorCancelButton")
                    .disabled(vm.isLoading)
                }
            }
            .safeAreaInset(edge: .bottom) {
                MeasuredBottomBar {
                    PrimaryButton(
                        title: L10n.categoryEditorSave.text,
                        icon: nil,
                        isLoading: vm.isLoading,
                        isDisabled: vm.isLoading || vm.name.trimmingCharacters(in: .whitespaces).isEmpty,
                        accessibilityId: "CategoryEditorSaveButton"
                    ) {
                        isNameFocused = false
                        Task { await save() }
                    }
                    .padding(.horizontal, Theme.screenHorizontalPadding)
                    .padding(.vertical, Theme.spacingSmall)
                    .frame(maxWidth: Theme.maxContentWidth)
                    .frame(maxWidth: .infinity)
                    .background(Theme.backgroundPrimary)
                }
            }
            .onPreferenceChange(BottomBarHeightPreferenceKey.self) { bottomBarHeight = $0 }
            .onAppear {
                isNameFocused = true
            }
            .onChange(of: vm.name) { _ in
                vm.clearFieldError()
            }
        }
        .navigationViewStyle(.stack)
    }

    private func save() async {
        let success = await vm.save()
        if success {
            dismiss()
        }
    }
}
