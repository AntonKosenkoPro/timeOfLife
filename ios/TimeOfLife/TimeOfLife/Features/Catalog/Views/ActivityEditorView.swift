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

    init(
        store: LocalStore,
        activity: Activity,
        onSaved: @escaping (Activity) -> Void,
        onCollision: @escaping (Activity) -> Void
    ) {
        _vm = StateObject(wrappedValue: ActivityEditorViewModel(
            store: store,
            activity: activity,
            onSaved: onSaved,
            onCollision: onCollision
        ))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingLarge) {
                    Text(L10n.activityEditorEditTitle.text)
                        .font(.title.bold())
                        .foregroundStyle(Theme.textPrimary)

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

                    Color.clear
                        .frame(height: Theme.spacingLarge)
                }
                .padding(.horizontal, Theme.screenHorizontalPadding)
                .frame(maxWidth: Theme.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.backgroundPrimary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.activityEditorCancel.text) {
                        dismiss()
                    }
                    .disabled(vm.isLoading)
                    .accessibilityIdentifier("ActivityEditorCancelButton")
                }
            }
            .safeAreaInset(edge: .bottom) {
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
            .onAppear {
                isNameFocused = true
            }
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(vm.isLoading)
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
                Text(L10n.activityEditorNoTags.text)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                TagSelector(
                    options: vm.availableCategories,
                    selected: $vm.selectedCategoryIDs,
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
