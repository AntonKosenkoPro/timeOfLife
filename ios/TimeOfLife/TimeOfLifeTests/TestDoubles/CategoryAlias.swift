import Foundation
@testable import TimeOfLife

/// Pins the same-module meaning of `Category` everywhere in `TimeOfLifeTests`.
///
/// The Objective-C runtime headers declare a top-level `Category`
/// (`typedef struct objc_category *Category`), which the current SDK
/// surfaces alongside `TimeOfLife.Category` in test files and makes bare
/// `Category` references ambiguous. This alias shadows both imported
/// candidates with the app's type (the underlying type is unchanged, so
/// `Codable`/`Equatable`/initializers all behave identically).
typealias Category = TimeOfLife.Category
