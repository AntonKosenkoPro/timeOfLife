import Foundation

/// The draft held by the shared Activity Editor (Design/SCREENS/
/// ActivityEditor.md). Name is the only required field; notes and Categories
/// are optional metadata.
struct ActivityDraft: Equatable {
    var name: String
    var notes: String?
    var categoryIDs: [String]

    init(name: String, notes: String? = nil, categoryIDs: [String] = []) {
        self.name = name
        self.notes = notes
        self.categoryIDs = categoryIDs
    }
}
