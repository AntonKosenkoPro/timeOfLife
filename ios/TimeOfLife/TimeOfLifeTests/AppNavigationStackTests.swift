import Testing
@testable import TimeOfLife

@MainActor
@Suite("AppNavigationStack")
struct AppNavigationStackTests {
    @Test("nested catalog route can pop without removing its parent")
    func nestedCatalogRoutePopsToManageActivities() {
        let navigation = AppNavigationStack()

        navigation.push(.manageActivities)
        navigation.push(.manageCategories)
        navigation.popTo(count: 1)

        #expect(navigation.path == [.manageActivities])
    }
}
