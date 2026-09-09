import SwiftUI

/// The Activity search content shown on Track while native search is active
/// (unify-activity-preparation-flow spec, decision 1/3/4; refine-selected-
/// activity-from-track change removes configured creation). The operating
/// system owns the search field, focus, keyboard, and Cancel; this view owns
/// the results surface: full-catalog browse, filtered matches, the prepared
/// checkmark, the unmatched quick-create row, empty-catalog guidance, and
/// localized validation/error states. Category metadata is never shown. The
/// view is generic over its host (`ActivitySearchHosting`) so the Log Time
/// sheet reuses the same content (manual-entry spec).
struct ActivitySearchContentView<VM: ActivitySearchHosting>: View {
    @ObservedObject var vm: VM

    var body: some View {
        Group {
            switch vm.searchResults {
            case let .browsing(activities):
                if activities.isEmpty {
                    emptyCatalog
                } else {
                    browseList(activities)
                }
            case let .searching(searching):
                searchingList(searching)
            }
        }
        .background(Theme.backgroundPrimary)
    }

    // MARK: - Empty query

    private func browseList(_ activities: [Activity]) -> some View {
        List {
            Section {
                ForEach(activities) { activity in
                    resultRow(activity)
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyCatalog: some View {
        VStack(spacing: Theme.spacingMedium) {
            Spacer()
            EmptyState(
                icon: "timer",
                title: L10n.timerSearchEmptyCatalogTitle.text,
                subtitle: L10n.timerSearchEmptyCatalogSubtitle.text
            )
            Spacer()
        }
        .padding(.horizontal, Theme.screenHorizontalPadding)
    }

    // MARK: - Non-empty query

    private func searchingList(_ searching: ActivitySearchResults.Searching) -> some View {
        List {
            matchesSection(searching)
            actionSection(searching)
            validationSection(searching)
            errorSection
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func matchesSection(_ searching: ActivitySearchResults.Searching) -> some View {
        if !searching.matches.isEmpty {
            Section {
                ForEach(searching.matches) { activity in
                    resultRow(activity)
                }
            }
        } else if searching.exactMatch == nil, searching.creationCandidate == nil, searching.pendingDeletion == nil {
            Section {
                Text(L10n.timerSearchNoResults.text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Theme.spacingMedium)
            }
        }
    }

    @ViewBuilder
    private func actionSection(_ searching: ActivitySearchResults.Searching) -> some View {
        if let pending = searching.pendingDeletion {
            Section {
                restoreRow(pending)
            }
        } else if let candidate = searching.creationCandidate {
            Section {
                createRow(candidate)
            }
        }
    }

    @ViewBuilder
    private func validationSection(_ searching: ActivitySearchResults.Searching) -> some View {
        if case .empty = searching.validation {
            Section {
                Text(L10n.timerSearchValidationEmpty.text)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .accessibilityIdentifier("ActivitySearchValidationError")
            }
        } else if case .tooLong = searching.validation {
            Section {
                Text(L10n.timerSearchValidationTooLong.text)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .accessibilityIdentifier("ActivitySearchValidationError")
            }
        }
    }

    @ViewBuilder private var errorSection: some View {
        if let errorMessage = vm.search.errorMessage {
            Section {
                ErrorBanner(
                    message: errorMessage,
                    accessibilityId: "ActivitySearchErrorBanner"
                )
                .padding(.vertical, Theme.spacingSmall)
            }
        }
    }
    // MARK: - Rows

    private func resultRow(_ activity: Activity) -> some View {
        Button {
            vm.confirmSearchResult(activity)
        } label: {
            HStack {
                Text(activity.name)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if vm.selectedActivityID == activity.id {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accentPrimary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: Theme.minTapArea)
        }
        .accessibilityLabel(String(format: L10n.timerSelectActivity.text, activity.name))
        .accessibilityValue(vm.selectedActivityID == activity.id ? L10n.timerReady.text : "")
        .accessibilityIdentifier("ActivitySearchResult(\(activity.id))")
    }

    private func restoreRow(_ pending: Activity) -> some View {
        Button {
            Task { await vm.restorePendingDeletion() }
        } label: {
            Label(
                String(format: L10n.timerSearchRestorePrompt.text, pending.name),
                systemImage: "arrow.uturn.backward.circle.fill"
            )
            .foregroundStyle(Theme.accentPrimary)
            .frame(minHeight: Theme.minTapArea)
        }
        .accessibilityLabel(String(format: L10n.timerSearchRestorePrompt.text, pending.name))
        .accessibilityIdentifier("ActivitySearchRestoreButton")
    }

    private func createRow(_ candidate: String) -> some View {
        Button {
            Task { await vm.quickCreateFromSearch() }
        } label: {
            Label(
                String(format: L10n.timerSearchCreate.text, candidate),
                systemImage: "plus.circle.fill"
            )
            .foregroundStyle(Theme.accentPrimary)
            .frame(maxWidth: .infinity, minHeight: Theme.minTapArea, alignment: .leading)
        }
        .accessibilityLabel(String(format: L10n.timerSearchCreate.text, candidate))
        .accessibilityIdentifier("ActivitySearchCreateButton")
    }
}

#if DEBUG
#Preview("Search — Empty Catalog") {
    ActivitySearchContentView(vm: TrackViewModel.preview(isSearchActive: true))
}

#Preview("Search — Browse Results") {
    let activities = [Activity(id: "reading", name: "Reading"), Activity(id: "work", name: "Deep work")]
    ActivitySearchContentView(vm: TrackViewModel.preview(activities: activities, isSearchActive: true))
}

#Preview("Search — Unmatched Creation") {
    ActivitySearchContentView(vm: TrackViewModel.preview(query: "Gym", isSearchActive: true))
}

#Preview("Search — Validation") {
    ActivitySearchContentView(vm: TrackViewModel.preview(
        query: String(repeating: "a", count: 61),
        isSearchActive: true
    ))
}

#Preview("Search — Filtered Results") {
    let activities = [Activity(id: "reading", name: "Reading"), Activity(id: "work", name: "Deep work")]
    ActivitySearchContentView(vm: TrackViewModel.preview(
        activities: activities,
        query: "read",
        isSearchActive: true
    ))
}
#endif
