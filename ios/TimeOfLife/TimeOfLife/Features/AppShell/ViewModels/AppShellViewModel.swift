import Foundation
import Combine

/// One push on a tab's navigation path (per-tab-navigation-paths).
///
/// `profile` opens the Profile page on the tab that pushed it; `entry`
/// carries the tapped History entry snapshot for the pushed unified entry
/// form (EDIT for `manual`, LOCKED for imported — resolved at the
/// destination, so the snapshot never changes spec behavior); `namePicker`
/// carries the Track draft snapshot for the pushed shared picker and
/// `notesEditor` the running draft's notes snapshot for the pushed notes
/// page (completion closures resolve at the destination from the owning
/// tab's view model, so the route itself stays a value). `categoryEditor`
/// carries nothing for the pushed inline category editor (create mode only;
/// completions likewise resolve at the destination). Remaining
/// caller-local `NavigationLink`s (Manage Categories from Profile, pickers
/// inside the entry form and sheets) always sit under a non-empty path or
/// outside any tab bar, so every push past a tab root is path-observed.
/// Path-driven pushes (profile, entry, the Track name picker, notes, and
/// category-editor routes) hide the tab bar through the owning stack's
/// path-driven visibility (app-shell "Tab bar hidden on pushed destinations");
/// only destinations reached through caller-local links (Manage Categories
/// from Profile, pickers inside the entry form and sheets — always under
/// a non-empty path or outside any tab bar) keep their own agreeing
/// backstop modifiers.
enum ShellRoute: Hashable {
    case profile
    case entry(TimeEntry)
    case namePicker(initialText: String)
    case notesEditor(initialText: String, entryName: String)
    /// Inline category creation from the running-tag row
    /// (inline-category-creation): create mode only, no payload — completions
    /// resolve at the destination from the owning tab's view model, so the
    /// route itself stays a value (namePicker precedent).
    case categoryEditor
}

/// View model for the app shell (app-shell spec): owns the selected
/// destination and one independent navigation path per tab.
@MainActor
final class AppShellViewModel: ObservableObject {
    enum Tab: Hashable {
        case track
        case history
        case insights
    }

    @Published var selectedTab: Tab = .track
    /// One independent push state per tab (per-tab-navigation-paths): opening
    /// Profile (or a History entry) on one tab never pre-pushes it on the
    /// others. Each tab's `NavigationStack(path:)` binds to its own path.
    @Published var trackPath: [ShellRoute] = []
    @Published var historyPath: [ShellRoute] = []
    @Published var insightsPath: [ShellRoute] = []

    /// Pushes Profile onto the selected tab's own path. A no-op when Profile
    /// is already on that path (the toolbar button is unreachable while
    /// pushed — the tab bar hides — so this guards programmatic double-taps).
    func openProfile() {
        switch selectedTab {
        case .track:
            if !trackPath.contains(.profile) { trackPath.append(.profile) }
        case .history:
            if !historyPath.contains(.profile) { historyPath.append(.profile) }
        case .insights:
            if !insightsPath.contains(.profile) { insightsPath.append(.profile) }
        }
    }

    /// Whether a path transition popped Profile (was present, now absent).
    /// Pushes to Categories (a caller-local link, not a path value) never
    /// touch the path, so this fires once-on-exit only — never for
    /// Categories/editor traffic.
    static func profileWasPopped(old: [ShellRoute], new: [ShellRoute]) -> Bool {
        old.contains(.profile) && !new.contains(.profile)
    }

    /// Whether a tab's stack hides the tab bar (fix-tab-bar-return-jump):
    /// the bar shows iff the tab sits at its root. Every push past a tab
    /// root is path-observed (path-driven pushes plus the Track name picker
    /// route; remaining caller-local links always sit under a non-empty
    /// path or outside any tab bar), so a stack-level declaration never
    /// disagrees with a destination backstop. Pure function of depth —
    /// unit-tested, no view state involved.
    static func isTabBarHidden(path: [ShellRoute]) -> Bool {
        !path.isEmpty
    }
}
