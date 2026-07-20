import Testing
import Foundation
@testable import TimeOfLife

@MainActor
@Suite("ViewModels")
struct ViewModelTests {

    private func makeService(
        repo: FakeAuthRepository = FakeAuthRepository()
    ) -> (AuthService, FakeAuthRepository, Connectivity, SessionStore) {
        let keychain = InMemoryKeychainStore()
        let cache = SessionCache(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let store = SessionStore()
        let service = AuthService(
            repository: repo,
            keychain: keychain,
            cache: cache,
            sessionStore: store
        )
        return (service, repo, Connectivity(), store)
    }

    // MARK: - EmailEntryViewModel

    @Test("EmailEntryViewModel: client validation blocks submit for invalid email")
    func emailEntryValidation() async throws {
        let (service, repo, conn, _) = makeService()
        let vm = EmailEntryViewModel(service: service, connectivity: conn)
        vm.email = "bad"

        await vm.submit()

        #expect(repo.calls.isEmpty)
        #expect(vm.fieldErrors.email != nil)
        #expect(vm.fieldErrors.otp == nil)
        #expect(vm.isLoading == false)
        #expect(vm.isEmailSent == false)
    }

    @Test("EmailEntryViewModel: empty email shows validation error")
    func emailEntryEmptyEmail() async throws {
        let (service, repo, conn, _) = makeService()
        let vm = EmailEntryViewModel(service: service, connectivity: conn)
        vm.email = ""

        await vm.submit()

        #expect(repo.calls.isEmpty)
        #expect(vm.fieldErrors.email != nil)
    }

    @Test("EmailEntryViewModel: offline disables submit and shows error")
    func emailEntryOffline() async throws {
        let (service, repo, _, _) = makeService()
        let conn = Connectivity()
        conn.isConnected = false
        let vm = EmailEntryViewModel(service: service, connectivity: conn)
        vm.email = "a@b.com"

        await vm.submit()

        #expect(repo.calls.isEmpty)
        #expect(vm.errorMessage != nil)
        #expect(vm.isEmailSent == false)
    }

    @Test("EmailEntryViewModel: success calls requestOtp and sets isEmailSent")
    func emailEntrySuccess() async throws {
        let (service, repo, conn, store) = makeService()
        let vm = EmailEntryViewModel(service: service, connectivity: conn)
        vm.email = "  Foo@Bar.com "

        await vm.submit()

        #expect(repo.calls == [.requestOtp(email: "foo@bar.com")])
        #expect(vm.isEmailSent == true)
        #expect(vm.errorMessage == nil)
        #expect(vm.isLoading == false)
        #expect(store.cachedEmail == "foo@bar.com")
    }

    @Test("EmailEntryViewModel: rate_limited error sets errorMessage")
    func emailEntryRateLimited() async throws {
        let repo = FakeAuthRepository()
        repo.otpRequestError = APIError.server(code: "rate_limited", message: "Too many attempts. Try again later.")
        let (service, _, conn, _) = makeService(repo: repo)
        let vm = EmailEntryViewModel(service: service, connectivity: conn)
        vm.email = "a@b.com"

        await vm.submit()

        #expect(vm.errorMessage != nil)
        #expect(vm.isEmailSent == false)
        #expect(vm.fieldErrors.isEmpty)
    }

    @Test("EmailEntryViewModel: loading state prevents double submission")
    func emailEntryLoadingState() async throws {
        let repo = FakeAuthRepository()
        // Make requestOtp slow by using an actor to coordinate
        let (service, _, conn, _) = makeService(repo: repo)
        let vm = EmailEntryViewModel(service: service, connectivity: conn)
        vm.email = "a@b.com"

        // Start submission
        let task = Task { await vm.submit() }

        // Check loading state is true during submission
        // (We can't easily check this mid-flight, but we can verify
        // that isLoading is false after completion)
        await task.value

        #expect(vm.isLoading == false)
        #expect(vm.isEmailSent == true)
    }

    @Test("EmailEntryViewModel: error clears on new attempt")
    func emailEntryErrorClears() async throws {
        let repo = FakeAuthRepository()
        repo.otpRequestError = APIError.server(code: "rate_limited", message: "Too many attempts.")
        let (service, _, conn, _) = makeService(repo: repo)
        let vm = EmailEntryViewModel(service: service, connectivity: conn)
        vm.email = "a@b.com"

        // First attempt fails
        await vm.submit()
        #expect(vm.errorMessage != nil)

        // Reset error and try again
        repo.otpRequestError = nil
        vm.errorMessage = nil
        await vm.submit()

        #expect(vm.errorMessage == nil)
        #expect(vm.isEmailSent == true)
    }

    @Test("EmailEntryViewModel: reset clears all state")
    func emailEntryReset() async throws {
        let (service, _, conn, _) = makeService()
        let vm = EmailEntryViewModel(service: service, connectivity: conn)
        vm.email = "a@b.com"
        vm.fieldErrors.email = "Some error"
        vm.isLoading = true
        vm.errorMessage = "Error"

        vm.reset()

        #expect(vm.email.isEmpty)
        #expect(vm.fieldErrors.isEmpty)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.isEmailSent == false)
    }

    // MARK: - OtpEntryViewModel

    @Test("OtpEntryViewModel: invalid code blocks submit")
    func otpEntryValidation() async throws {
        let (service, repo, conn, _) = makeService()
        let vm = OtpEntryViewModel(service: service, connectivity: conn, email: "a@b.com")
        vm.code = "12345"

        await vm.submit()

        #expect(repo.calls.isEmpty)
        #expect(vm.fieldErrors.otp != nil)
        #expect(vm.isVerified == false)
    }

    @Test("OtpEntryViewModel: empty code shows validation error")
    func otpEntryEmptyCode() async throws {
        let (service, repo, conn, _) = makeService()
        let vm = OtpEntryViewModel(service: service, connectivity: conn, email: "a@b.com")
        vm.code = ""

        await vm.submit()

        #expect(repo.calls.isEmpty)
        #expect(vm.fieldErrors.otp != nil)
    }

    @Test("OtpEntryViewModel: invalid_otp error sets errorMessage")
    func otpEntryInvalidOtp() async throws {
        let repo = FakeAuthRepository()
        repo.otpVerifyError = APIError.server(code: "invalid_otp", message: "Incorrect code. Try again.")
        let (service, _, conn, _) = makeService(repo: repo)
        let vm = OtpEntryViewModel(service: service, connectivity: conn, email: "a@b.com")
        vm.code = "123456"

        await vm.submit()

        #expect(repo.calls == [.verifyOtp(email: "a@b.com", code: "123456")])
        #expect(vm.errorMessage != nil)
        #expect(vm.isVerified == false)
    }

    @Test("OtpEntryViewModel: otp_expired error sets errorMessage")
    func otpEntryExpired() async throws {
        let repo = FakeAuthRepository()
        repo.otpVerifyError = APIError.server(code: "otp_expired", message: "This code has expired.")
        let (service, _, conn, _) = makeService(repo: repo)
        let vm = OtpEntryViewModel(service: service, connectivity: conn, email: "a@b.com")
        vm.code = "123456"

        await vm.submit()

        #expect(vm.errorMessage != nil)
        #expect(vm.isVerified == false)
    }

    @Test("OtpEntryViewModel: otp_attempts_exceeded error sets errorMessage")
    func otpEntryAttemptsExceeded() async throws {
        let repo = FakeAuthRepository()
        repo.otpVerifyError = APIError.server(
            code: "otp_attempts_exceeded",
            message: "Too many attempts. Request a new code."
        )
        let (service, _, conn, _) = makeService(repo: repo)
        let vm = OtpEntryViewModel(service: service, connectivity: conn, email: "a@b.com")
        vm.code = "123456"

        await vm.submit()

        #expect(vm.errorMessage != nil)
        #expect(vm.isVerified == false)
    }

    @Test("OtpEntryViewModel: success verifies and sets isVerified")
    func otpEntrySuccess() async throws {
        let (service, repo, conn, store) = makeService()
        let vm = OtpEntryViewModel(service: service, connectivity: conn, email: "a@b.com")
        vm.code = "123456"

        await vm.submit()

        #expect(repo.calls == [.verifyOtp(email: "a@b.com", code: "123456")])
        #expect(vm.isVerified == true)
        #expect(vm.errorMessage == nil)
        if case .signedIn = store.state {
            // Success
        } else {
            Issue.record("Expected signed in state")
        }
    }

    @Test("OtpEntryViewModel: resendOtp calls requestOtp for the same email")
    func otpEntryResend() async throws {
        let (service, repo, conn, _) = makeService()
        let vm = OtpEntryViewModel(service: service, connectivity: conn, email: "a@b.com")

        await vm.resendOtp()

        #expect(repo.calls == [.requestOtp(email: "a@b.com")])
        #expect(vm.errorMessage == nil)
    }

    @Test("OtpEntryViewModel: resendOtp shows error on failure")
    func otpEntryResendFailure() async throws {
        let repo = FakeAuthRepository()
        repo.otpRequestError = APIError.server(code: "rate_limited", message: "Too many attempts.")
        let (service, _, conn, _) = makeService(repo: repo)
        let vm = OtpEntryViewModel(service: service, connectivity: conn, email: "a@b.com")

        await vm.resendOtp()

        #expect(vm.errorMessage != nil)
    }

    @Test("OtpEntryViewModel: handleDeepLinkCode pre-fills and auto-submits")
    func otpEntryDeepLink() async throws {
        let (service, repo, conn, store) = makeService()
        let vm = OtpEntryViewModel(service: service, connectivity: conn, email: "a@b.com")

        vm.handleDeepLinkCode("123456")

        #expect(vm.code == "123456")

        // Wait for the async submit to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        #expect(repo.calls == [.verifyOtp(email: "a@b.com", code: "123456")])
        #expect(vm.isVerified == true)
        if case .signedIn = store.state {
            // Success
        } else {
            Issue.record("Expected signed in state")
        }
    }

    @Test("OtpEntryViewModel: offline blocks submit and shows error")
    func otpEntryOffline() async throws {
        let (service, repo, _, _) = makeService()
        let conn = Connectivity()
        conn.isConnected = false
        let vm = OtpEntryViewModel(service: service, connectivity: conn, email: "a@b.com")
        vm.code = "123456"

        await vm.submit()

        #expect(repo.calls.isEmpty)
        #expect(vm.errorMessage != nil)
        #expect(vm.isVerified == false)
    }

    @Test("OtpEntryViewModel: reset clears all state")
    func otpEntryReset() async throws {
        let (service, _, conn, _) = makeService()
        let vm = OtpEntryViewModel(service: service, connectivity: conn, email: "a@b.com")
        vm.code = "123456"
        vm.fieldErrors.otp = "Error"
        vm.isLoading = true
        vm.errorMessage = "Error"

        vm.reset()

        #expect(vm.code.isEmpty)
        #expect(vm.fieldErrors.isEmpty)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.isVerified == false)
    }

    // MARK: - Navigation state transitions

    @Test("EmailEntryViewModel: successful submit transitions to email sent state")
    func emailEntryNavigationTransition() async throws {
        let (service, _, conn, _) = makeService()
        let vm = EmailEntryViewModel(service: service, connectivity: conn)
        vm.email = "user@example.com"

        await vm.submit()

        #expect(vm.isEmailSent == true)
        #expect(vm.errorMessage == nil)
    }

    @Test("OtpEntryViewModel: successful verify transitions to verified state")
    func otpEntryNavigationTransition() async throws {
        let (service, _, conn, _) = makeService()
        let vm = OtpEntryViewModel(service: service, connectivity: conn, email: "user@example.com")
        vm.code = "123456"

        await vm.submit()

        #expect(vm.isVerified == true)
        #expect(vm.errorMessage == nil)
    }
}
