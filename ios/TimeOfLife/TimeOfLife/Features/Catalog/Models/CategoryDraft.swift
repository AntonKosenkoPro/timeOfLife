import Foundation

/// The draft held by the Category Editor (Design/SCREENS/CategoryEditor.md,
/// category-management D4). Name and icon are both required to save; the
/// icon defaults to `tag` in create mode.
struct CategoryDraft: Equatable {
    var name: String
    var icon: CatalogIcon

    init(name: String, icon: CatalogIcon = .default) {
        self.name = name
        self.icon = icon
    }
}
