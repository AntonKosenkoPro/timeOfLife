import SwiftUI

struct CategoryEditorView: View {
    @ObservedObject var vm: CategoryEditorViewModel
    @Environment(\.dismiss)
    private var dismiss
    @FocusState private var isNameFocused: Bool
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
        .modifier(CategoryEditorDetents())
    }

    private var editorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingLarge) {
                Text(title)
                    .font(.title.bold())
                    .foregroundStyle(Theme.textPrimary)

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
                    Task { await vm.save() }
                }
                .focused($isNameFocused)
                .disabled(vm.isLoading)

                SectionHeader(title: L10n.categoryEditorColorLabel.text)
                ColorSwatchGrid(
                    options: ActivityColor.allCases,
                    selection: Binding(
                        get: { vm.color },
                        set: { vm.color = $0 ?? .mint }
                    ),
                    accessibilityId: "CategoryEditorColor",
                    disabled: vm.isLoading
                )

                if let message = vm.errorMessage {
                    ErrorBanner(message: message, accessibilityId: "CategoryEditorErrorBanner")
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
            VStack(spacing: Theme.spacingSmall) {
                Spacer().frame(height: Theme.spacingLarge)
                PrimaryButton(
                    title: L10n.categoryEditorSave.text,
                    icon: nil,
                    isLoading: vm.isLoading,
                    isDisabled: vm.isLoading || vm.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    accessibilityId: "CategoryEditorSaveButton"
                ) {
                    isNameFocused = false
                    Task { await vm.save() }
                }
            }
            .padding(.horizontal, Theme.screenHorizontalPadding)
            .padding(.vertical, Theme.spacingSmall)
            .frame(maxWidth: Theme.maxContentWidth)
            .frame(maxWidth: .infinity)
            .background(Theme.backgroundPrimary)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(L10n.categoryEditorCancel.text) { vm.cancel() }
                    .disabled(vm.isLoading)
                    .accessibilityIdentifier("CategoryEditorCancelButton")
            }
        }
        .onAppear { isNameFocused = true }
        .onChange(of: vm.name) { _ in vm.clearNameError() }
        .onChange(of: vm.onSaveResult) { result in
            guard let result else { return }
            switch result {
            case .saved, .reused, .cancelled:
                isNameFocused = false
                dismiss()
            case .conflict:
                break
            }
        }
    }

    private var title: String {
        switch vm.mode {
        case .create:
            return L10n.categoryEditorCreateTitle.text
        case .edit:
            return L10n.categoryEditorEditTitle.text
        }
    }
}

private struct CategoryEditorDetents: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.presentationDetents([.medium])
        } else {
            content
        }
    }
}

#if DEBUG

#Preview("Category Editor — Create EN") {
    let container = AppContainer.production()
    return CategoryEditorView(vm: CategoryEditorViewModel(
        mode: .create,
        store: container.catalogStore,
        repository: container.catalogRepository,
        service: container.catalogService,
        connectivity: container.connectivity
    ))
    .environmentObject(container)
}

#Preview("Category Editor — Edit RU Dark") {
    let container = AppContainer.production()
    return CategoryEditorView(vm: CategoryEditorViewModel(
        mode: .edit(.sampleBlue),
        store: container.catalogStore,
        repository: container.catalogRepository,
        service: container.catalogService,
        connectivity: container.connectivity
    ))
    .environmentObject(container)
    .preferredColorScheme(.dark)
    .environment(\.locale, .init(identifier: "ru"))
}

#Preview("Category Editor — Validation") {
    let container = AppContainer.production()
    let viewModel = CategoryEditorViewModel(
        mode: .create,
        store: container.catalogStore,
        repository: container.catalogRepository,
        service: container.catalogService,
        connectivity: container.connectivity
    )
    viewModel.name = String(repeating: "x", count: 61)
    viewModel.setPreviewValidation()
    return CategoryEditorView(vm: viewModel)
        .environmentObject(container)
}

#Preview("Category Editor — Saving") {
    let container = AppContainer.production()
    let viewModel = CategoryEditorViewModel(
        mode: .edit(.sampleBlue),
        store: container.catalogStore,
        repository: container.catalogRepository,
        service: container.catalogService,
        connectivity: container.connectivity
    )
    viewModel.setPreviewLoading()
    return CategoryEditorView(vm: viewModel)
        .environmentObject(container)
}

#endif
