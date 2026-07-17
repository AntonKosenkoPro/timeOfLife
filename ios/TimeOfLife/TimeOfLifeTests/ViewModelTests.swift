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

    // MARK: - EmailEntry

    @Test("EmailEntryViewModel: client validation blocks submit")
    func emailEntryValidation() async throws {
        let (service, repo, conn, _) = makeService()
        let vm = EmailEntryViewModel(service: service, connectivity: conn)
        vm.email = "bad"
        await vm.submit()
        #expect(repo.calls.isEmpty)
        #expect(vm.fieldErrors.email != nil)
        #expect(vm.fieldErrors.otp == nil)
        #expect(vm.isSubmitting == false)
    }

    @Test("EmailEntryViewModel: offline disables submit")
    func emailEntryOffline() async throws {
        let (service, repo, _, _) = makeService()
        let conn = Connectivity()
        conn.isConnected = false
        let vm = EmailEntryViewModel(service: service, connectivity: conn)
        vm.email = "a@b.com"
        await vm.submit()
        #expect(repo.calls.isEmpty)
        #expect(vm.submitError != nil)
    }

    @Test("EmailEntryViewModel: success calls requestOtp, caches email, fires onSuccess")
    func emailEntrySuccess() async throws {
        let (service, repo, _, store) = makeService()
        let vm = EmailEntryViewModel(service: service, connectivity: Connectivity())
        var navigated: String?
        vm.onSuccess = { navigated = $0 }
        vm.email = "  Foo@Bar.com "
        await vm.submit()
        #expect(repo.calls == [.requestOtp(email: "foo@bar.com")])
        #expect(vm.successMessage != nil)
        #expect(navigated == "foo@bar.com")
        #expect(store.cachedEmail == "foo@bar.com")
    }

    @Test("EmailEntryViewModel: rate_limited maps to top-level error")
    func emailEntryRateLimited() async throws {
        let repo = FakeAuthRepository()
        repo.otpRequestError = APIError.server(code: "rate_limited", message: "slow")
        let (service, _, _, _) = makeService(repo: repo)
        let vm = EmailEntryViewModel(service: service, connectivity: Connectivity())
        vm.email = "a@b.com"
        await vm.submit()
        #expect(vm.submitError != nil)
        #expect(vm.fieldErrors.isEmpty)
    }

    // MARK: - OtpEntry

    @Test("OtpEntryViewModel: invalid code blocks submit")
    func otpEntryValidation() async throws {
        let (service, repo, _, _) = makeService()
        let vm = OtpEntryViewModel(service: service, connectivity: Connectivity(), email: "a@b.com")
        vm.code = "12345"
        await vm.verify()
        #expect(repo.calls.isEmpty)
        #expect(vm.fieldErrors.otp != nil)
    }

    @Test("OtpEntryViewModel: invalid_otp maps to field error")
    func otpEntryInvalidOtp() async throws {
        let repo = FakeAuthRepository()
        repo.otpVerifyError = APIError.server(code: "invalid_otp", message: "wrong")
        let (service, _, _, _) = makeService(repo: repo)
        let vm = OtpEntryViewModel(service: service, connectivity: Connectivity(), email: "a@b.com")
        vm.code = "123456"
        await vm.verify()
        #expect(repo.calls == [.verifyOtp(email: "a@b.com", code: "123456")])
        #expect(vm.fieldErrors.otp != nil)
        #expect(vm.submitError == nil)
    }

    @Test("OtpEntryViewModel: otp_expired maps to field error")
    func otpEntryExpired() async throws {
        let repo = FakeAuthRepository()
        repo.otpVerifyError = APIError.server(code: "otp_expired", message: "old")
        let (service, _, _, _) = makeService(repo: repo)
        let vm = OtpEntryViewModel(service: service, connectivity: Connectivity(), email: "a@b.com")
        vm.code = "123456"
        await vm.verify()
        #expect(vm.fieldErrors.otp != nil)
    }

    @Test("OtpEntryViewModel: otp_attempts_exceeded maps to top-level error")
    func otpEntryAttemptsExceeded() async throws {
        let repo = FakeAuthRepository()
        repo.otpVerifyError = APIError.server(code: "otp_attempts_exceeded", message: "locked")
        let (service, _, _, _) = makeService(repo: repo)
        let vm = OtpEntryViewModel(service: service, connectivity: Connectivity(), email: "a@b.com")
        vm.code = "123456"
        await vm.verify()
        #expect(vm.submitError != nil)
        #expect(vm.fieldErrors.isEmpty)
    }

    @Test("OtpEntryViewModel: success verifies and signs in")
    func otpEntrySuccess() async throws {
        let (service, repo, _, store) = makeService()
        let vm = OtpEntryViewModel(service: service, connectivity: Connectivity(), email: "a@b.com")
        var called = false
        vm.onSuccess = { called = true }
        vm.code = "123456"
        await vm.verify()
        #expect(repo.calls == [.verifyOtp(email: "a@b.com", code: "123456")])
        #expect(called == true)
        if case .signedIn = store.state {} else { Issue.record("expected signed in") }
    }

    @Test("OtpEntryViewModel: resend calls requestOtp for the same email")
    func otpEntryResend() async throws {
        let (service, repo, _, _) = makeService()
        let vm = OtpEntryViewModel(service: service, connectivity: Connectivity(), email: "a@b.com")
        await vm.resend()
        #expect(repo.calls == [.requestOtp(email: "a@b.com")])
        #expect(vm.successMessage != nil)
    }

    @Test("OtpEntryViewModel: autofill pre-fill via pendingDeepLinkCode + auto-submit")
    func otpEntryAutofill() async throws {
        let (service, repo, _, store) = makeService()
        let nav = AppNavigationStack()
        nav.pendingDeepLinkCode = "123456"
        let vm = OtpEntryViewModel(service: service, connectivity: Connectivity(), email: "a@b.com")
        // Simulate OtpEntryView.consumeDeepLinkCodeIfNeeded(): pre-fill code,
        // clear the side channel, and auto-submit when email + code present.
        let code = nav.pendingDeepLinkCode
        nav.pendingDeepLinkCode = nil
        if let code { vm.code = code }
        if !vm.email.isEmpty && !vm.code.isEmpty {
            await vm.verify()
        }
        #expect(code == "123456")
        #expect(repo.calls == [.verifyOtp(email: "a@b.com", code: "123456")])
        if case .signedIn = store.state {} else { Issue.record("expected signed in") }
    }

    // MARK: - Offline disabling

    @Test("isOffline reflects connectivity")
    func offlineFlag() {
        let (service, _, _, _) = makeService()
        let conn = Connectivity()
        conn.isConnected = false
        let vm = EmailEntryViewModel(service: service, connectivity: conn)
        #expect(vm.isOffline == true)
    }
}