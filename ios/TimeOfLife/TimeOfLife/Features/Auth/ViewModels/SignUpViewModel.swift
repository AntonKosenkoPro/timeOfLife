import Foundation
import Combine

/// Shared base for auth view models: holds submit state and maps server
/// errors to either a field error or a top-level `submitError`.
@MainActor
class AuthViewModelBase: ObservableObject {
    @Published var isSubmitting: Bool = false
    @Published var submitError: String?
    @Published var fieldErrors: FieldErrors = .empty
    @Published var successMessage: String?

    let service: AuthService
    let connectivity: Connectivity

    init(service: AuthService, connectivity: Connectivity) {
        self.service = service
        self.connectivity = connectivity
    }

    var isOffline: Bool { !connectivity.isConnected }

    /// Resets transient state before a fresh submit.
    func resetTransient() {
        submitError = nil
        fieldErrors = .empty
        successMessage = nil
    }

    /// Maps an `APIError` into either field errors or a top-level message.
    /// Returns `true` if the error was mapped to a field (UI should keep
    /// focus), `false` if it became `submitError`.
    func mapServer(error: APIError) -> Bool {
        guard case let .server(code, _, details) = error else {
            submitError = ErrorLocalization.message(for: error)
            return false
        }
        switch code {
        case "email_taken":
            fieldErrors = FieldErrors(email: [NSLocalizedString("error.email_taken", comment: "")], password: [])
            return true
        case "weak_password":
            // details.rule_violations may carry backend reasons; surface a
            // single top-level weak-password message for the MVP.
            _ = details
            fieldErrors = FieldErrors(email: [], password: [NSLocalizedString("error.weak_password", comment: "")])
            return true
        default:
            submitError = L10n.text(in: .default, code: code)
            return false
        }
    }
}

@MainActor
final class SignUpViewModel: AuthViewModelBase {
    @Published var email: String = ""
    @Published var password: String = ""
    var onSuccess: (() -> Void)?

    override init(service: AuthService, connectivity: Connectivity) {
        super.init(service: service, connectivity: connectivity)
    }

    func submit() async {
        resetTransient()
        let emailErrors = AuthValidator.validateEmail(email)
        let passwordErrors = AuthValidator.validatePassword(password)
        if !emailErrors.isEmpty || !passwordErrors.isEmpty {
            fieldErrors = FieldErrors(
                email: emailErrors.map { $0.text },
                password: passwordErrors.map { $0.text }
            )
            return
        }
        guard !isOffline else {
            submitError = NSLocalizedString("error.offline", comment: "")
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await service.signUp(email: email, password: password)
            successMessage = NSLocalizedString("signup.success", comment: "")
            onSuccess?()
        } catch let error as APIError {
            _ = mapServer(error: error)
        } catch {
            submitError = NSLocalizedString("error.unknown", comment: "")
        }
    }
}