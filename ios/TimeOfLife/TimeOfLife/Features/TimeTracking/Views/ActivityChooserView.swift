import SwiftUI

/// The searchable native sheet for selecting or creating the Activity to
/// prepare on Track (Design/COMPONENTS.md, `ActivityChooser`). Category names
/// and icons are never shown here — capture chooses Activities by name.
struct ActivityChooserView: View {
    @ObservedObject var vm: TrackViewModel
    @Environment(\.dismiss)
    private var dismiss
    @State private var firstName = ""
    @State private var isNamingFirstActivity = false
    var body: some View {
        NavigationView {
            Group {
                if vm.activities.isEmpty && vm.chooserQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    emptyCatalog
                } else {
                    list
                }
            }
            .searchable(text: $vm.chooserQuery, prompt: L10n.timerChooserSearchPrompt.text)
            .navigationTitle(L10n.timerChooserTitle.text)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.signOutCancel.text) { dismiss() }
                }
            }
            .alert(L10n.timerChooserCreateFirst.text, isPresented: $isNamingFirstActivity) {
                TextField(L10n.timerActivityPlaceholder.text, text: $firstName)
                Button(L10n.timerStart.text) {
                    let name = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    Task { await vm.createActivity(named: name) }
                }
                Button(L10n.signOutCancel.text, role: .cancel) {}
            }
        }
        .navigationViewStyle(.stack)
        .accessibilityIdentifier("ActivityChooser")
    }

    private var list: some View {
        List {
            Section(vm.chooserQuery.trimmingCharacters(in: .whitespaces).isEmpty
                    ? L10n.timerChooserRecent.text
                    : L10n.timerChooserActivities.text) {
                ForEach(vm.filteredActivities) { activity in
                    Button {
                        vm.select(activity)
                    } label: {
                        HStack {
                            Text(activity.name)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(minHeight: Theme.minTapArea)
                    }
                    .accessibilityLabel("Select \(activity.name)")
                }

                if vm.canCreateFromQuery {
                    Button {
                        let name = vm.chooserQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { await vm.createActivity(named: name) }
                    } label: {
                        Label(
                            String(format: L10n.timerChooserCreate.text, vm.chooserQuery.trimmingCharacters(in: .whitespacesAndNewlines)),
                            systemImage: "plus.circle.fill"
                        )
                        .foregroundStyle(Theme.accentPrimary)
                        .frame(minHeight: Theme.minTapArea)
                    }
                    .accessibilityIdentifier("ActivityChooserCreateButton")
                }
            }

            Section {
                Button {
                    dismiss()
                    vm.isChoosingActivity = false
                } label: {
                    Label(L10n.timerManageActivities.text, systemImage: "square.grid.2x2")
                        .foregroundStyle(Theme.textPrimary)
                        .frame(minHeight: Theme.minTapArea)
                }
            }
        }
    }

    private var emptyCatalog: some View {
        VStack(spacing: Theme.spacingMedium) {
            Spacer()
            EmptyState(
                icon: "timer",
                title: L10n.timerChooserEmptyTitle.text,
                subtitle: L10n.timerChooserEmptySubtitle.text
            )
            PrimaryButton(
                title: L10n.timerChooserCreateFirst.text,
                icon: "plus",
                isLoading: false,
                isDisabled: false,
                accessibilityId: "ActivityChooserCreateFirstButton"
            ) {
                firstName = ""
                isNamingFirstActivity = true
            }
            .padding(.horizontal, Theme.screenHorizontalPadding)
            Spacer()
        }
        .background(Theme.backgroundPrimary)
    }
}

#if DEBUG
#Preview("Activity Chooser") {
    let container = AppContainer.production()
    ActivityChooserView(vm: TrackViewModel(
        service: container.timerService,
        connectivity: container.connectivity
    ))
    .environmentObject(container)
}
#endif
