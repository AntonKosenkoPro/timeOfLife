import Foundation
import Combine

/// Observable session state the `RootView` observes. `AuthService` is the only
/// writer; views read. Holds only non-secret state — tokens live in Keychain.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var state: SessionState = .signedOut
    @Published private(set) var cachedEmail: String?

    enum SessionState: Equatable {
        case signedOut
        case signedIn(CachedSession)
    }

    init() {}

    func setSignedIn(_ session: CachedSession) {
        state = .signedIn(session)
        cachedEmail = session.email
    }

    func setSignedOut() {
        state = .signedOut
        cachedEmail = nil
    }

    func setCachedEmail(_ email: String?) {
        cachedEmail = email
    }
}
