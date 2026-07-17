import Foundation
import Combine

@MainActor
final class ResetPasswordViewModel: AuthViewModelBase {
    @Published var password: String = ""
    let token: String
    var onSuccess: (() -> Void)?

    init(service: AuthService, connectivity: Connectivity, token: String) {
        self.token = token
        super.init(service: service, connectivity: connectivity)
    }

    func submit() async {
        resetTransient()
        let passwordErrors = AuthValidator.validatePassword(password)
        if !passwordErrors.isEmpty {
            fieldErrors = FieldErrors(email: [], password: passwordErrors.map { $0.text })
            return
        }
        guard !isOffline else {
            submitError = NSLocalizedString("error.offline", comment: "")
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await service.confirmPasswordReset(token: token, newPassword: password)
            successMessage = NSLocalizedString("reset.success", comment: "")
            onSuccess?()
        } catch let error as APIError {
            _ = mapServer(error: error)
        } catch {
            submitError = NSLocalizedString("error.unknown", comment: "")
        }
    }

    override func mapServer(error: APIError) -> Bool {
        if case let .server(code, _, _) = error {
            switch code {
            case "weak_password":
                fieldErrors = FieldErrors(email: [], password: [NSLocalizedString("error.weak_password", comment: "")])
                return true
            default:
                break
            }
        }
        return super.mapServer(error: error)
    }
}