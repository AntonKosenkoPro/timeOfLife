import SwiftUI

/// Activity Editor sheet (F1/F3/F7/U1/U2). Shared create/edit sheet.
struct ActivityEditorView: View {
    @StateObject var vm: ActivityEditorViewModel
    @Environment(\.dismiss)
    private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var bottomBarHeight: CGFloat = 0

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.spacingLarge) {
                    Text(vm.editingActivity != nil
                        ? L10n.activityEditorEditTitle.text
                        : L10n.activityEditorCreateTitle.text)
                        .font(.title.bold())
                        .foregroundStyle(Theme.textPrimary)

                    TextFieldWithError(
                        title: L10n.activityEditorNameLabel.text,
                        placeholder: L10n.activityEditorNamePlaceholder.text,
                        text: $vm.name,
                        error: vm.fieldError,
                        keyboardType: .default,
                        textContentType: nil,
                        submitLabel: .done,
                        autocapitalization: .sentences,
                        accessibilityId: "ActivityEditorNameField"
                    ) {
                        isNameFocused = false
                        Task { await save() }
                    }
                    .focused($isNameFocused)

                    // Notes
                    VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                        Text(L10n.activityEditorNotesLabel.text)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        TextEditor(text: $vm.notes)
                            .frame(minHeight: 96)
                            .padding(Theme.spacingMedium)
                            .background(Theme.backgroundSecondary)
                            .cornerRadius(Theme.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                    .stroke(Theme.hairline, lineWidth: 1))
                            .accessibilityIdentifier("ActivityEditorNotesField")
                        Text(String(format: L10n.activityEditorNotesCounter.text, vm.notes.count))
                            .font(.caption)
                            .foregroundStyle(vm.notes.count > 280 ? Theme.danger : Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    // Tags
                    SectionHeader(title: L10n.activityEditorTagsLabel.text)
                    TagSelector(
                        options: vm.availableCategories,
                        selected: $vm.selectedCategoryIds,
                        accessibilityId: "ActivityEditorTags")

                    if let errorMessage = vm.errorMessage {
                        ErrorBanner(message: errorMessage, accessibilityId: "ActivityEditorErrorBanner")
                    }

                    Color.clear.frame(height: bottomBarHeight + Theme.spacingLarge)
                }
                .padding(.horizontal, Theme.screenHorizontalPadding)
                .padding(.top, Theme.spacingLarge)
                .frame(maxWidth: Theme.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(vm.editingActivity != nil
                ? L10n.activityEditorEditTitle.text
                : L10n.activityEditorCreateTitle.text)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.activityEditorCancel.text) {
                        dismiss()
                    }
                    .accessibilityIdentifier("ActivityEditorCancelButton")
                    .disabled(vm.isLoading)
                }
            }
            .safeAreaInset(edge: .bottom) {
                MeasuredBottomBar {
                    PrimaryButton(
                        title: L10n.activityEditorSave.text,
                        icon: nil,
                        isLoading: vm.isLoading,
                        isDisabled: vm.isLoading || vm.name.trimmingCharacters(in: .whitespaces).isEmpty,
                        accessibilityId: "ActivityEditorSaveButton"
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
                Task { await vm.loadCategories() }
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
