import SwiftUI

/// Pure suggestion filter for the name picker (name-picker spec):
/// case-insensitive prefix over all committed exact-text names,
/// newest-first. The exact match is included — typing a full existing name
/// narrows the list to its row (plus any longer prefix matches) instead of
/// showing a misleading "new name" hint. `Gym` ≠ `GYM` identity is preserved
/// by the case-sensitive row identity. An empty trimmed input lists
/// everything (the picker is browsable without typing).
enum NamePickerFilter {
    static func suggestions(
        for draft: String,
        in recents: [ExactName]
    ) -> [ExactName] {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return recents }
        let lowered = trimmed.lowercased()
        return recents.filter { $0.text.lowercased().hasPrefix(lowered) }
    }
}

/// The shared dedicated name-picking page (name-picker spec): an
/// autofocused entry field pinned at the top with a scrollable suggestion
/// list below. Pushed on the caller's `NavigationStack` — the standard
/// system Back is the cancel path (the local draft is discarded, the caller
/// is untouched), so this view needs no chrome of its own.
///
/// Completion is exactly two paths, both caller-owned: tapping a row calls
/// `onCompleteSuggestion` (fill exact text + ordered categories), keyboard
/// Done with non-empty text calls `onCompleteText` (typed text, exact-match
/// inheritance resolved by the caller). Done with empty text is a no-op.
struct NamePicker: View {
    /// Caller recents, newest-first, already capped (the picker reads only).
    let recents: [ExactName]
    /// The id→Category map for row icons.
    let categories: [String: Category]
    /// Field placeholder (each caller passes its own copy).
    let placeholder: String
    /// Hint shown when there are no recents and nothing is typed.
    let emptyHint: String
    /// Row-tap completion (exact text + ordered categories).
    let onCompleteSuggestion: (ExactName) -> Void
    /// Done-with-text completion (typed text).
    let onCompleteText: (String) -> Void

    /// Local draft: the caller sees exactly one update, on completion —
    /// keystrokes never touch caller state (Back then cancels for free).
    @State private var draft: String
    @FocusState private var fieldFocused: Bool
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize
    @Environment(\.dismiss)
    private var dismiss

    init(
        initialText: String,
        recents: [ExactName],
        categories: [String: Category],
        placeholder: String,
        emptyHint: String,
        onCompleteSuggestion: @escaping (ExactName) -> Void,
        onCompleteText: @escaping (String) -> Void
    ) {
        self.recents = recents
        self.categories = categories
        self.placeholder = placeholder
        self.emptyHint = emptyHint
        self.onCompleteSuggestion = onCompleteSuggestion
        self.onCompleteText = onCompleteText
        _draft = State(initialValue: initialText)
    }

    var body: some View {
        VStack(spacing: 0) {
            fieldCard
            suggestionList
        }
        .padding(.horizontal, Theme.screenHorizontalPadding)
        .frame(maxWidth: Theme.maxContentWidth)
        // Pin to the top: without the maxHeight the stack centers itself
        // when the content is short, so the field rides up and down as
        // results switch between rows and hints.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle(L10n.namePickerTitle.text)
        .navigationBarTitleDisplayMode(.inline)
        // Pushed from Track (path-observed via ShellRoute.namePicker), the
        // entry form, or the Log Time sheet (per-tab-navigation-paths).
        // Every reachable context sits under a non-empty path or outside
        // any tab bar, so this destination modifier is only a backstop that
        // always agrees with the owning stack's path-driven visibility
        // (fix-tab-bar-return-jump) — never a conflict. No-op inside the
        // sheet stack, which owns no tab bar.
        .toolbar(.hidden, for: .tabBar)
        .background(Theme.backgroundPrimary.ignoresSafeArea())
        .task {
            // Autofocus waits out the push transition: focusing instantly
            // fires the keyboard mid-push, and the keyboard-driven relayout
            // makes the covered Track screen visibly jump before the picker
            // lands. Cancelled automatically on pop.
            guard await FocusDelay.settle() else { return }
            fieldFocused = true
        }
    }

    // MARK: - Entry field (pinned)

    private var fieldCard: some View {
        FieldCard {
            HStack(spacing: 0) {
                TextField(
                    placeholder,
                    text: $draft,
                    onCommit: completeWithTypedText
                )
                .focused($fieldFocused)
                .submitLabel(.done)
                .font(.body)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapArea)
                .accessibilityIdentifier("NamePickerField")
                .accessibilityLabel(placeholder)
                if ClearButtonVisibility.shouldShow(
                    isFocused: fieldFocused,
                    text: draft
                ) {
                    ClearTextButton(
                        action: { draft = "" },
                        accessibilityId: "NamePickerClearButton"
                    )
                }
            }
        }
        .padding(.vertical, Theme.spacingMedium)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Suggestion list (scrollable)

    /// One persistent scroll container for every state (rows, empty hint,
    /// no-match hint): the container never swaps type, so switching states
    /// cannot move the field or jump the content — only the inner rows
    /// change. The top padding is constant across states for the same
    /// reason. Rows render lazily since the source is uncapped.
    @ViewBuilder private var suggestionList: some View {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = NamePickerFilter.suggestions(for: draft, in: recents)
        ScrollView {
            if !trimmed.isEmpty, filtered.isEmpty {
                Text(String(format: L10n.namePickerNoMatchHint.text, trimmed))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("NamePickerNoMatchHint")
            } else if filtered.isEmpty {
                Text(emptyHint)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("NamePickerEmptyHint")
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, suggestion in
                        Button {
                            complete(with: suggestion)
                        } label: {
                            suggestionLabel(suggestion)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("NamePickerSuggestion\(index)")
                        if index < filtered.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, Theme.spacingMedium)
                .background(Theme.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .stroke(Theme.hairline, lineWidth: 0.7)
                }
            }
        }
        // Scroll-away dismisses the keyboard (native interactive behavior).
        .scrollDismissesKeyboard(.interactively)
        .padding(.top, Theme.spacingSmall)
        .accessibilityIdentifier("NamePickerSuggestions")
        .accessibilityLabel(L10n.namePickerTitle.text)
    }

    private func suggestionLabel(_ suggestion: ExactName) -> some View {
        HStack(spacing: Theme.spacingExtraSmall) {
            suggestionIcon(suggestion)
            Text(suggestion.text)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: Theme.minTapArea)
        .contentShape(Rectangle())
    }

    /// Leading icon slot, always rendered (History/Insights convention):
    /// the first category's validated symbol, or the `questionmark`
    /// fallback when the newest entry carries no categories. Unlike the
    /// Recents chips (which omit the icon to save space), the list keeps
    /// the slot so every row's text aligns. The slot scales with Dynamic
    /// Type, mirroring `RecentActivitiesChips`.
    private func suggestionIcon(_ suggestion: ExactName) -> some View {
        let symbol: String
        if let categoryID = suggestion.firstCategoryID,
           let category = categories[categoryID] {
            symbol = CatalogIcon(validated: category.icon).displaySymbol
        } else {
            symbol = "questionmark"
        }
        return Image(systemName: symbol)
            .font(.body)
            .foregroundStyle(Theme.textSecondary)
            .frame(width: symbolSlotSize)
            .accessibilityHidden(true)
    }

    /// Fixed icon slot so the text column aligns across rows.
    private var symbolSlotSize: CGFloat {
        DynamicTypeMetrics.symbolSlotSize(
            basePointSize: 17,
            textStyle: .body,
            dynamicTypeSize: dynamicTypeSize
        )
    }

    /// Keyboard Done: applies the typed text. Empty input is a no-op —
    /// Back remains the exit (applying empty has no consumer: Track would
    /// idle and the form gate would disable, so there is nothing to gain).
    private func completeWithTypedText() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        resignAndPop { onCompleteText(trimmed) }
    }

    /// Row tap: applies the exact text plus its ordered categories.
    private func complete(with suggestion: ExactName) {
        resignAndPop { onCompleteSuggestion(suggestion) }
    }

    /// Resigns focus BEFORE popping so the keyboard dismissal runs
    /// concurrently with the pop transition: resigning implicitly during
    /// the pop dismisses the keyboard after Track is revealed, and its
    /// relayout makes Track visibly jump down.
    private func resignAndPop(apply: () -> Void) {
        fieldFocused = false
        apply()
        dismiss()
    }
}

#if DEBUG
#Preview("Name Picker — Matches") {
    NavigationStack {
        NamePicker(
            initialText: "Gy",
            recents: [
                ExactName(text: "Gym", categoryIDs: ["c1"], firstCategoryID: "c1"),
                ExactName(text: "Gymnastics", categoryIDs: [], firstCategoryID: nil)
            ],
            categories: ["c1": Category(id: "c1", name: "Sport", icon: "figure.run")],
            placeholder: L10n.timerNamePlaceholder.text,
            emptyHint: L10n.timerRecentsEmptyHint.text,
            onCompleteSuggestion: { _ in },
            onCompleteText: { _ in }
        )
    }
}

#Preview("Name Picker — Empty") {
    NavigationStack {
        NamePicker(
            initialText: "",
            recents: [],
            categories: [:],
            placeholder: L10n.timerNamePlaceholder.text,
            emptyHint: L10n.timerRecentsEmptyHint.text,
            onCompleteSuggestion: { _ in },
            onCompleteText: { _ in }
        )
    }
}

#Preview("Name Picker — No Match") {
    NavigationStack {
        NamePicker(
            initialText: "Zzz",
            recents: [
                ExactName(text: "Gym", categoryIDs: [], firstCategoryID: nil)
            ],
            categories: [:],
            placeholder: L10n.timerNamePlaceholder.text,
            emptyHint: L10n.timerRecentsEmptyHint.text,
            onCompleteSuggestion: { _ in },
            onCompleteText: { _ in }
        )
    }
}
#endif
