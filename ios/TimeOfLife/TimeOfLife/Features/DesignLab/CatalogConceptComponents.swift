#if DEBUG
import SwiftUI

struct ActivityConceptRow: View {
    let activity: ConceptActivity

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(PrototypePalette.primaryText)
                HStack(spacing: 6) {
                    Text(activity.categories.isEmpty ? "No category" : activity.categories.joined(separator: ", "))
                    Text("·")
                    Text(activity.lastUsed)
                }
                .font(.caption)
                .foregroundStyle(PrototypePalette.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PrototypePalette.secondaryText)
        }
        .frame(minHeight: 54)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Activity, \(activity.name)")
        .accessibilityValue(activity.categories.isEmpty ? "No category" : activity.categories.joined(separator: ", "))
    }
}

struct CategoryConceptRow: View {
    let category: ConceptCategory

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: category.icon)
                .font(.body)
                .foregroundStyle(PrototypePalette.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(category.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(PrototypePalette.primaryText)
                Text(category.summary)
                    .font(.caption)
                    .foregroundStyle(PrototypePalette.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PrototypePalette.secondaryText)
        }
        .frame(minHeight: 54)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Category, \(category.name)")
        .accessibilityValue(category.summary)
    }
}

struct ActivityPickerConcept: View {
    let activities: [ConceptActivity]
    @Binding var selectedActivity: String
    @Environment(\.dismiss)
    private var dismiss
    @State private var query = ""

    private var results: [ConceptActivity] {
        guard !query.isEmpty else { return activities }
        return activities.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(results) { activity in
                        Button {
                            selectedActivity = activity.name
                            dismiss()
                        } label: {
                            Text(activity.name)
                                .foregroundStyle(PrototypePalette.primaryText)
                                .frame(minHeight: 44)
                        }
                    }

                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && results.isEmpty {
                        Button("Create \"\(query)\"") {
                            selectedActivity = query.trimmingCharacters(in: .whitespacesAndNewlines)
                            dismiss()
                        }
                        .foregroundStyle(PrototypePalette.accent)
                    }
                } header: {
                    Text("Activities")
                } footer: {
                    Text("Choose a concrete task. Categories can be added later in the activity editor.")
                }
            }
            .searchable(text: $query, prompt: "Search activities")
            .navigationTitle("Choose Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.light)
        .accessibilityIdentifier("CatalogConceptActivityPickerSheet")
    }
}

struct ActivityEditorConcept: View {
    @Environment(\.dismiss)
    private var dismiss
    @State private var name = "Morning walk with a dog"
    @State private var notes = ""
    @State private var selectedCategories: Set<String> = ["Sport"]

    private let availableCategories = ["Sport", "Work", "Learning"]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("New activity")
                        .font(.title.bold())
                        .foregroundStyle(PrototypePalette.primaryText)

                    TextField("Activity name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("CatalogConceptActivityNameField")
                    TextField("Notes · optional", text: $notes)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("CatalogConceptActivityNotesField")

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Categories")
                                .font(.headline)
                                .foregroundStyle(PrototypePalette.primaryText)
                            Text("OPTIONAL")
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(1.2)
                                .foregroundStyle(PrototypePalette.secondaryText)
                        }
                        Text("Use categories only when you want this activity included in an Insights lens.")
                            .font(.footnote)
                            .foregroundStyle(PrototypePalette.secondaryText)
                        HStack(spacing: 8) {
                            ForEach(availableCategories, id: \.self) { category in
                                CategoryChip(
                                    name: category,
                                    selected: selectedCategories.contains(category)
                                ) {
                                    if selectedCategories.contains(category) {
                                        selectedCategories.remove(category)
                                    } else {
                                        selectedCategories.insert(category)
                                    }
                                }
                            }
                        }
                        .accessibilityIdentifier("CatalogConceptCategorySelection")
                    }
                }
                .padding(24)
            }
            .background(PrototypePalette.canvas.ignoresSafeArea())
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Save activity") { dismiss() }
                    .font(.body.bold())
                    .foregroundStyle(PrototypePalette.canvas)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(PrototypePalette.primaryText)
                    .clipShape(Capsule())
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(PrototypePalette.canvas)
                    .accessibilityIdentifier("CatalogConceptSaveActivityButton")
            }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.light)
        .accessibilityIdentifier("CatalogConceptActivityEditor")
    }
}

struct CategoryChip: View {
    let name: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(name, systemImage: selected ? "checkmark" : "plus")
                .font(.caption.weight(.medium))
                .foregroundStyle(selected ? .white : PrototypePalette.primaryText)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(selected ? PrototypePalette.accent : PrototypePalette.surface)
                .clipShape(Capsule())
                .overlay {
                    if !selected {
                        Capsule().stroke(PrototypePalette.hairline, lineWidth: 0.8)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Category, \(name)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }
}

struct CategoryEditorConcept: View {
    @Environment(\.dismiss)
    private var dismiss
    @State private var name = "Wellbeing"
    @State private var selectedIcon = "heart.fill"

    private let icons = ["briefcase.fill", "figure.run", "book.fill", "heart.fill", "house.fill", "tag.fill"]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("New category")
                        .font(.title.bold())
                        .foregroundStyle(PrototypePalette.primaryText)

                    TextField("Category name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("CatalogConceptCategoryNameField")

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Icon")
                            .font(.headline)
                            .foregroundStyle(PrototypePalette.primaryText)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                            ForEach(icons, id: \.self) { icon in
                                Button {
                                    selectedIcon = icon
                                } label: {
                                    Image(systemName: icon)
                                        .font(.title3)
                                        .foregroundStyle(selectedIcon == icon ? .white : PrototypePalette.primaryText)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 48)
                                        .background(selectedIcon == icon ? PrototypePalette.accent : PrototypePalette.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Icon \(icon)")
                                .accessibilityValue(selectedIcon == icon ? "Selected" : "Not selected")
                            }
                        }
                        .accessibilityIdentifier("CatalogConceptIconSelection")
                    }
                }
                .padding(24)
            }
            .background(PrototypePalette.canvas.ignoresSafeArea())
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Save category") { dismiss() }
                    .font(.body.bold())
                    .foregroundStyle(PrototypePalette.canvas)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(PrototypePalette.primaryText)
                    .clipShape(Capsule())
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(PrototypePalette.canvas)
                    .accessibilityIdentifier("CatalogConceptSaveCategoryButton")
            }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.light)
        .accessibilityIdentifier("CatalogConceptCategoryEditor")
    }
}
#endif
