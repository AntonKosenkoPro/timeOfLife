import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("ViewModels")
struct ViewModelTests {
    private func makeService(repo: FakeAuthRepository = FakeAuthRepository()) -> (AuthService, FakeAuthRepository, Connectivity, SessionStore) {
        let keychain = InMemoryKeychainStore()
        let cache = SessionCache(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let store = SessionStore()
        let service = AuthService(repository: repo, keychain: keychain, cache: cache, sessionStore: store)
        return (service, repo, Connectivity(), store)
    }

    // MARK: - SignUp

    @Test("SignUpViewModel: client validation blocks submit")
    func signUpValidation() async throws {
        let (service, repo, conn, _) = makeService()
        let vm = SignUpViewModel(service: service, connectivity: conn)
        vm.email = "bad"
        vm.password = "123"
        await vm.submit()
        #expect(repo.calls.isEmpty)
        #expect(!vm.fieldErrors.email.isEmpty)
        #expect(!vm.fieldErrors.password.isEmpty)
        #expect(vm.isSubmitting == false)
    }

    @Test("SignUpViewModel: offline disables submit")
    func signUpOffline() async throws {
        let (service, repo, _, _) = makeService()
        let conn = Connectivity()
        conn.isConnected = false
        let vm = SignUpViewModel(service: service, connectivity: conn)
        vm.email = "a@b.com"
        vm.password = "abcd1234"
        await vm.submit()
        #expect(repo.calls.isEmpty)
        #expect(vm.submitError != nil)
    }

    @Test("SignUpViewModel: success sets successMessage and calls onSuccess")
    func signUpSuccess() async throws {
        let (service, repo, _, store) = makeService()
        let vm = SignUpViewModel(service: service, connectivity: Connectivity())
        var called = false
        vm.onSuccess = { called = true }
        vm.email = "a@b.com"
        vm.password = "abcd1234"
        await vm.submit()
        #expect(repo.calls.first == .signup(email: "a@b.com", password: "abcd1234"))
        #expect(vm.successMessage != nil)
        #expect(called == true)
        #expect(store.cachedEmail == "a@b.com")
    }

    @Test("SignUpViewModel: email_taken maps to field error")
    func signUpEmailTaken() async throws {
        let repo = FakeAuthRepository()
        repo.signupError = APIError.server(code: "email_taken", message: "taken")
        let (service, _, _, _) = makeService(repo: repo)
        let vm = SignUpViewModel(service: service, connectivity: Connectivity())
        vm.email = "a@b.com"
        vm.password = "abcd1234"
        await vm.submit()
        #expect(!vm.fieldErrors.email.isEmpty)
    }

    // MARK: - SignIn

    @Test("SignInViewModel: invalid_credentials maps to top-level error")
    func signInInvalidCredentials() async throws {
        let repo = FakeAuthRepository()
        repo.signinError = APIError.server(code: "invalid_credentials", message: "bad")
        let (service, _, _, _) = makeService(repo: repo)
        let vm = SignInViewModel(service: service, connectivity: Connectivity())
        vm.email = "a@b.com"
        vm.password = "abcd1234"
        await vm.submit()
        #expect(vm.submitError != nil)
        #expect(vm.fieldErrors.isEmpty)
    }

    @Test("SignInViewModel: email_not_verified shows server message")
    func signInNotVerified() async throws {
        let repo = FakeAuthRepository()
        repo.signinError = APIError.server(code: "email_not_verified", message: "verify")
        let (service, _, _, _) = makeService(repo: repo)
        let vm = SignInViewModel(service: service, connectivity: Connectivity())
        vm.email = "a@b.com"
        vm.password = "abcd1234"
        await vm.submit()
        #expect(vm.submitError != nil)
    }

    @Test("SignInViewModel: success signs in")
    func signInSuccess() async throws {
        let (service, _, _, store) = makeService()
        let vm = SignInViewModel(service: service, connectivity: Connectivity())
        vm.email = "a@b.com"
        vm.password = "abcd1234"
        await vm.submit()
        if case .signedIn = store.state {} else { Issue.record("expected signed in") }
    }

    // MARK: - ForgotPassword

    @Test("ForgotPasswordViewModel: always-202 success")
    func forgotSuccess() async throws {
        let (service, repo, _, _) = makeService()
        let vm = ForgotPasswordViewModel(service: service, connectivity: Connectivity())
        vm.email = "a@b.com"
        await vm.submit()
        #expect(repo.calls == [.requestPasswordReset(email: "a@b.com")])
        #expect(vm.successMessage != nil)
    }

    @Test("ForgotPasswordViewModel: invalid email blocks submit")
    func forgotValidation() async throws {
        let (service, repo, _, _) = makeService()
        let vm = ForgotPasswordViewModel(service: service, connectivity: Connectivity())
        vm.email = "bad"
        await vm.submit()
        #expect(repo.calls.isEmpty)
        #expect(!vm.fieldErrors.email.isEmpty)
    }

    // MARK: - ResetPassword

    @Test("ResetPasswordViewModel: weak_password maps to field error")
    func resetWeakPassword() async throws {
        let repo = FakeAuthRepository()
        repo.resetConfirmError = APIError.server(code: "weak_password", message: "weak")
        let (service, _, _, _) = makeService(repo: repo)
        let vm = ResetPasswordViewModel(service: service, connectivity: Connectivity(), token: "tok")
        vm.password = "abcd1234"
        await vm.submit()
        #expect(!vm.fieldErrors.password.isEmpty)
    }

    @Test("ResetPasswordViewModel: success")
    func resetSuccess() async throws {
        let (service, repo, _, _) = makeService()
        let vm = ResetPasswordViewModel(service: service, connectivity: Connectivity(), token: "tok")
        vm.password = "abcd1234"
        await vm.submit()
        #expect(repo.calls == [.confirmPasswordReset(token: "tok", newPassword: "abcd1234")])
        #expect(vm.successMessage != nil)
    }

    @Test("ResetPasswordViewModel: validation blocks short password")
    func resetValidation() async throws {
        let (service, repo, _, _) = makeService()
        let vm = ResetPasswordViewModel(service: service, connectivity: Connectivity(), token: "tok")
        vm.password = "ab1"
        await vm.submit()
        #expect(repo.calls.isEmpty)
        #expect(!vm.fieldErrors.password.isEmpty)
    }

    // MARK: - VerifyEmail

    @Test("VerifyEmailViewModel: success verifies and signs in")
    func verifySuccess() async throws {
        let (service, repo, _, store) = makeService()
        let vm = VerifyEmailViewModel(service: service, connectivity: Connectivity(), token: "tok")
        await vm.submit()
        #expect(repo.calls == [.verifyEmail(token: "tok")])
        if case .signedIn = store.state {} else { Issue.record("expected signed in") }
    }

    @Test("VerifyEmailViewModel: empty token shows invalid message")
    func verifyEmptyToken() async throws {
        let (service, repo, _, _) = makeService()
        let vm = VerifyEmailViewModel(service: service, connectivity: Connectivity(), token: "")
        await vm.submit()
        #expect(repo.calls.isEmpty)
        #expect(vm.submitError != nil)
    }

    @Test("VerifyEmailViewModel: resend uses cached email")
    func verifyResend() async throws {
        let (service, repo, _, store) = makeService()
        store.setCachedEmail("a@b.com")
        let vm = VerifyEmailViewModel(service: service, connectivity: Connectivity(), token: "tok")
        await vm.resend()
        #expect(repo.calls == [.resendVerification(email: "a@b.com")])
    }

    // MARK: - Offline disabling

    @Test("isOffline reflects connectivity")
    func offlineFlag() {
        let (service, _, _, _) = makeService()
        let conn = Connectivity()
        conn.isConnected = false
        let vm = SignInViewModel(service: service, connectivity: conn)
        #expect(vm.isOffline == true)
    }
}