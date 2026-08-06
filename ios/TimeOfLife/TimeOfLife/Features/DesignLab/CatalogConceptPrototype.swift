#if DEBUG
import SwiftUI

enum CatalogConceptTab: String, CaseIterable {
    case capture = "Track"
    case activities = "Activities"
    case categories = "Categories"
}

struct ConceptActivity: Identifiable {
    let id = UUID()
    let name: String
    let lastUsed: String
    let categories: [String]
}

struct ConceptCategory: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let summary: String
}

struct CatalogConceptPrototype: View {
    @State private var tab: CatalogConceptTab = .capture
    @State private var selectedActivity = "Morning walk with a dog"
    @State private var showPicker = false
    @State private var showActivityEditor = false
    @State private var showCategoryEditor = false

    private let activities = [
        ConceptActivity(
            name: "Morning walk with a dog",
            lastUsed: "Used today",
            categories: ["Sport"]
        ),
        ConceptActivity(
            name: "Preparing quarterly report",
            lastUsed: "Used yesterday",
            categories: ["Work"]
        ),
        ConceptActivity(
            name: "Read Atomic Habits",
            lastUsed: "Used 3 days ago",
            categories: []
        )
    ]

    private let categories = [
        ConceptCategory(
            name: "Work",
            icon: "briefcase.fill",
            summary: "4 activities · 12h 40m"
        ),
        ConceptCategory(
            name: "Sport",
            icon: "figure.run",
            summary: "2 activities · 3h 20m"
        ),
        ConceptCategory(
            name: "Learning",
            icon: "book.fill",
            summary: "2 activities · 1h 45m"
        )
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                tabPicker
                content
            }
            .background(PrototypePalette.canvas.ignoresSafeArea())
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if tab == .activities {
                        Button {
                            showActivityEditor = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add activity")
                        .accessibilityIdentifier("CatalogConceptAddActivityButton")
                    } else if tab == .categories {
                        Button {
                            showCategoryEditor = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add category")
                        .accessibilityIdentifier("CatalogConceptAddCategoryButton")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showPicker) {
            ActivityPickerConcept(
                activities: activities,
                selectedActivity: $selectedActivity
            )
        }
        .sheet(isPresented: $showActivityEditor) {
            ActivityEditorConcept()
        }
        .sheet(isPresented: $showCategoryEditor) {
            CategoryEditorConcept()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activity and category relationship study")
    }

    private var tabPicker: some View {
        Picker("Catalog context", selection: $tab) {
            ForEach(CatalogConceptTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .accessibilityIdentifier("CatalogConceptContextPicker")
    }

    private var navigationTitle: String {
        tab == .capture ? "Track" : tab.rawValue
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .capture:
            captureContent
        case .activities:
            activitiesContent
        case .categories:
            categoriesContent
        }
    }

    private var captureContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("READY")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(PrototypePalette.secondaryText)
                    .padding(.top, 20)

                Button { showPicker = true } label: {
                    HStack(spacing: 7) {
                        Text(selectedActivity)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.headline)
                    .foregroundStyle(PrototypePalette.primaryText)
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("Activity, \(selectedActivity)")
                .accessibilityIdentifier("CatalogConceptActivityPicker")

                VStack(spacing: 8) {
                    Text("00:00")
                        .font(.system(size: 78, weight: .ultraLight, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(PrototypePalette.primaryText)
                    Text("READY TO START")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.8)
                        .foregroundStyle(PrototypePalette.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 76)

                Button {} label: {
                    Text("Start")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PrototypePalette.canvas)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(PrototypePalette.primaryText)
                        .clipShape(Capsule())
                }
                .accessibilityIdentifier("CatalogConceptStartButton")
                .padding(.top, 30)

                VStack(alignment: .leading, spacing: 12) {
                    Text("RECENT ACTIVITIES")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(PrototypePalette.secondaryText)

                    ForEach(activities) { activity in
                        Button { selectedActivity = activity.name } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(activity.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(PrototypePalette.primaryText)
                                    Text(activity.lastUsed)
                                        .font(.caption)
                                        .foregroundStyle(PrototypePalette.secondaryText)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(PrototypePalette.secondaryText)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 58)
                            .background(PrototypePalette.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .accessibilityLabel("Select activity, \(activity.name)")
                    }
                }
                .padding(.top, 42)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
    }

    private var activitiesContent: some View {
        List {
            Section {
                ForEach(activities) { activity in
                    ActivityConceptRow(activity: activity)
                }
            } header: {
                Text("Concrete tasks you can track")
            }

            Section {
                Button { showActivityEditor = true } label: {
                    Label("New activity", systemImage: "plus.circle.fill")
                }
            } footer: {
                Text("Categories are optional metadata used later in Insights.")
            }
        }
        .listStyle(.insetGrouped)
        .background(PrototypePalette.canvas)
        .accessibilityIdentifier("CatalogConceptActivitiesList")
    }

    private var categoriesContent: some View {
        List {
            Section {
                ForEach(categories) { category in
                    CategoryConceptRow(category: category)
                }
            } header: {
                Text("Broad lenses for Insights")
            } footer: {
                Text("Categories do not define an activity and are never required to start a timer.")
            }

            Section {
                Label("Uncategorized", systemImage: "tray")
                    .foregroundStyle(PrototypePalette.secondaryText)
            } footer: {
                Text("Activities without a category remain valid and appear here in analysis.")
            }
        }
        .listStyle(.insetGrouped)
        .background(PrototypePalette.canvas)
        .accessibilityIdentifier("CatalogConceptCategoriesList")
    }
}
#endif
