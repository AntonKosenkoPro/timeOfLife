import SwiftUI

struct ActivityEditorView: View {
    @ObservedObject var vm: ActivityEditorViewModel
    @EnvironmentObject private var container: AppContainer
    @Environment(\.dismiss)
    private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var showCategoryEditor = false
    @State private var bottomBarHeight: CGFloat = 0

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack { editorContent }
            } else {
                NavigationView { editorContent }
                    .navigationViewStyle(.stack)
            }
        }
        .modifier(ActivityEditorDetents())
        .interactiveDismissDisabled(vm.isLoading)
    }

    private var editorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingLarge) {
                Text(title)
                    .font(.title.bold())
                    .foregroundStyle(Theme.textPrimary)

                TextFieldWithError(
                    title: L10n.activityEditorNameLabel.text,
                    placeholder: L10n.activityEditorNamePlaceholder.text,
                    text: $vm.draft.name,
                    error: vm.fieldErrors.name,
                    keyboardType: .default,
                    textContentType: nil,
                    submitLabel: .done,
                    autocapitalization: .sentences,
                    accessibilityId: "ActivityEditorNameField"
                ) {
                    isNameFocused = false
                    Task { await vm.save() }
                }
                .focused($isNameFocused)

                notesSection

                SectionHeader(title: L10n.activityEditorTagsLabel.text)
                TagSelector(
                    options: vm.availableCategories,
                    selected: Binding(
                        get: { vm.draft.categoryIds },
                        set: { vm.draft.categoryIds = $0 }
                    ),
                    accessibilityId: "ActivityEditorTags"
                )
                if vm.availableCategories.isEmpty {
                    HStack {
                        Text(L10n.activityEditorNoTags.text)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                        Button(L10n.activityEditorAddCategory.text) {
                            showCategoryEditor = true
                        }
                        .font(.subheadline)
                        .foregroundStyle(Theme.accentPrimary)
                        .accessibilityIdentifier("ActivityEditorAddCategoryButton")
                    }
                }

                if let error = vm.errorMessage {
                    ErrorBanner(message: error, accessibilityId: "ActivityEditorErrorBanner")
                }

                Color.clear.frame(height: bottomBarHeight + Theme.spacingLarge)
            }
            .padding(.horizontal, Theme.screenHorizontalPadding)
            .padding(.top, Theme.spacingLarge)
            .frame(maxWidth: Theme.maxContentWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.backgroundPrimary.ignoresSafeArea())
        .measuredBottomBar(height: $bottomBarHeight) {
            PrimaryButton(
                title: L10n.activityEditorSave.text,
                icon: nil,
                isLoading: vm.isLoading,
                isDisabled: vm.draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                accessibilityId: "ActivityEditorSaveButton"
            ) {
                isNameFocused = false
                Task { await vm.save() }
            }
            .padding(.horizontal, Theme.screenHorizontalPadding)
            .padding(.vertical, Theme.spacingSmall)
            .background(Theme.backgroundPrimary)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(L10n.activityEditorCancel.text) { vm.cancel() }
                    .disabled(vm.isLoading)
                    .accessibilityIdentifier("ActivityEditorCancelButton")
            }
        }
        .onAppear {
            isNameFocused = vm.shouldFocusName
            Task { await vm.loadCategories() }
        }
        .onChange(of: vm.draft.name) { _ in vm.clearNameError() }
        .onChange(of: vm.draft.notes) { _ in vm.clearNotesError() }
        .onChange(of: vm.onSaveResult) { result in
            if result != nil { dismiss() }
        }
        .sheet(isPresented: $showCategoryEditor) {
            let editor = CategoryEditorViewModel(
                mode: .create,
                store: container.catalogStore,
                repository: container.catalogRepository,
                service: container.catalogService,
                connectivity: container.connectivity
            )
            CategoryEditorView(vm: editor)
                .onChange(of: editor.onSaveResult) { result in
                    guard let result else { return }
                    switch result {
                    case let .saved(category):
                        addCategory(category)
                    case let .reused(category):
                        addCategory(category)
                        vm.errorMessage = L10n.errorCategoryExists.text
                    case let .conflict(category):
                        vm.errorMessage = L10n.errorConflict.text
                        if let index = vm.availableCategories.firstIndex(where: { $0.id == category.id }) {
                            vm.availableCategories[index] = category
                        }
                    case .cancelled:
                        break
                    }
                }
        }
    }

    private func addCategory(_ category: Category) {
        if !vm.availableCategories.contains(where: { $0.id == category.id }) {
            vm.availableCategories.append(category)
            vm.availableCategories.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        vm.draft.categoryIds.append(category.id)
        showCategoryEditor = false
    }

    private var title: String {
        switch vm.mode {
        case .edit: return L10n.activityEditorEditTitle.text
        case .createFromManage, .createFromTimer: return L10n.activityEditorCreateTitle.text
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text(L10n.activityEditorNotesLabel.text)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $vm.draft.notes)
                    .frame(minHeight: 96)
                    .padding(Theme.spacingSmall)
                    .background(Theme.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerRadius)
                            .stroke(Theme.hairline, lineWidth: 1)
                    )
                if vm.draft.notes.isEmpty {
                    Text(L10n.activityEditorNotesPlaceholder.text)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, Theme.spacingMedium)
                        .padding(.vertical, Theme.spacingMedium)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityIdentifier("ActivityEditorNotesField")
            HStack {
                Spacer()
                Text(L10n.activityEditorNotesCounter.text(vm.draft.notes.count))
                    .font(.caption)
                    .foregroundStyle(vm.draft.notes.count > 280 ? Theme.danger : Theme.textSecondary)
            }
        }
    }
}

private struct ActivityEditorDetents: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.presentationDetents([.medium, .large])
        } else {
            content
        }
    }
}

#if DEBUG

private let editorPreviewActivity = Activity(
    id: UUID(), name: "Reading",
    notes: "Morning reading", lastUsedAt: Date(), categoryIds: [Category.sampleBlue.id],
    createdAt: Date().addingTimeInterval(-3600), updatedAt: Date()
)

#Preview("Activity Editor — Create EN") {
    let container = AppContainer.production()
    ActivityEditorView(vm: ActivityEditorViewModel(
        mode: .createFromManage, store: container.catalogStore,
        repository: container.catalogRepository, service: container.catalogService,
        connectivity: container.connectivity
    )).environmentObject(container)
}

#Preview("Activity Editor — Create RU Dark") {
    let container = AppContainer.production()
    return ActivityEditorView(vm: ActivityEditorViewModel(
        mode: .createFromManage, store: container.catalogStore,
        repository: container.catalogRepository, service: container.catalogService,
        connectivity: container.connectivity
    ))
    .environmentObject(container)
    .preferredColorScheme(.dark)
    .environment(\.locale, .init(identifier: "ru"))
}

#Preview("Activity Editor — Edit EN Light") {
    let container = AppContainer.production()
    return ActivityEditorView(vm: ActivityEditorViewModel(
        mode: .edit(editorPreviewActivity), store: container.catalogStore,
        repository: container.catalogRepository, service: container.catalogService,
        connectivity: container.connectivity, availableCategories: [Category.sampleBlue]
    )).environmentObject(container)
}

#Preview("Activity Editor — Edit RU Dark") {
    let container = AppContainer.production()
    ActivityEditorView(vm: ActivityEditorViewModel(
        mode: .edit(editorPreviewActivity), store: container.catalogStore,
        repository: container.catalogRepository, service: container.catalogService,
        connectivity: container.connectivity, availableCategories: [Category.sampleBlue]
    ))
    .environmentObject(container)
    .preferredColorScheme(.dark)
    .environment(\.locale, .init(identifier: "ru"))
}

#endif
