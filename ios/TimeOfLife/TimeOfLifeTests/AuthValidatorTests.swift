import Testing
import Foundation
@testable import TimeOfLife

@Suite("AuthValidator")
struct AuthValidatorTests {
    // MARK: Email

    @Test("empty email is invalid")
    func emptyEmail() {
        #expect(AuthValidator.validateEmail("") == [.emailEmpty])
        #expect(AuthValidator.validateEmail("   ") == [.emailEmpty])
    }

    @Test("invalid email shapes are rejected")
    func invalidEmail() {
        #expect(AuthValidator.validateEmail("notanemail").contains(.emailInvalid))
        #expect(AuthValidator.validateEmail("a@").contains(.emailInvalid))
        #expect(AuthValidator.validateEmail("a@b").contains(.emailInvalid))
        #expect(AuthValidator.validateEmail("a@b.c").contains(.emailInvalid))
    }

    @Test("valid email passes")
    func validEmail() {
        #expect(AuthValidator.validateEmail("user@example.com").isEmpty)
        #expect(AuthValidator.validateEmail("User.Name+1@sub.example.co").isEmpty)
    }

    @Test("email longer than 254 is too long")
    func tooLongEmail() {
        let local = String(repeating: "a", count: 250)
        #expect(AuthValidator.validateEmail("\(local)@b.co").contains(.emailTooLong))
    }

    @Test("normalize trims and lowercases")
    func normalize() {
        #expect(AuthValidator.normalize(email: "  Foo@Bar.COM ") == "foo@bar.com")
    }

    // MARK: OTP (Requirements U1: exactly 6 digits)

    @Test("empty code is invalid")
    func emptyCode() {
        #expect(AuthValidator.validateOtpCode("") == [.otpEmpty])
        #expect(AuthValidator.validateOtpCode("   ") == [.otpEmpty])
    }

    @Test("too-short code is invalid")
    func shortCode() {
        #expect(AuthValidator.validateOtpCode("12345").contains(.otpInvalid))
    }

    @Test("too-long code is invalid")
    func longCode() {
        #expect(AuthValidator.validateOtpCode("1234567").contains(.otpInvalid))
    }

    @Test("non-digit code is invalid")
    func nonDigitCode() {
        #expect(AuthValidator.validateOtpCode("abcdef").contains(.otpInvalid))
        #expect(AuthValidator.validateOtpCode("12a456").contains(.otpInvalid))
    }

    @Test("valid 6-digit code passes")
    func validCode() {
        #expect(AuthValidator.validateOtpCode("123456").isEmpty)
        #expect(AuthValidator.validateOtpCode("000000").isEmpty)
    }

    @Test("combined validate maps to fields")
    func combinedFields() {
        let r = AuthValidator.validate(email: "bad", code: "123")
        #expect(r[.email]?.contains(.emailInvalid) == true)
        #expect(r[.otp]?.contains(.otpInvalid) == true)
    }

    @Test("combined validate with nil code only checks email")
    func combinedEmailOnly() {
        let r = AuthValidator.validate(email: "", code: nil)
        #expect(r[.email]?.contains(.emailEmpty) == true)
        #expect(r[.otp] == nil)
    }

    // MARK: Unified messages (Requirements U4)

    @Test("valid fields produce no message")
    func unifiedNone() {
        #expect(AuthValidator.unifiedEmailMessage([]) == nil)
        #expect(AuthValidator.unifiedOtpMessage([]) == nil)
    }

    @Test("empty code yields a single 'required' message")
    func unifiedEmptyCode() {
        let msg = AuthValidator.unifiedOtpMessage([.otpEmpty])
        #expect(msg != nil)
        #expect(msg == NSLocalizedString("validation.otpEmpty", comment: ""))
    }

    @Test("invalid code yields a single unified message")
    func unifiedInvalidCode() {
        let expected = NSLocalizedString("validation.otp.prefix", comment: "") + " "
            + NSLocalizedString("validation.otp.rule.invalid", comment: "") + "."
        #expect(AuthValidator.unifiedOtpMessage([.otpInvalid]) == expected)
        #expect(AuthValidator.unifiedOtpMessage([.otpInvalid, .otpEmpty]) == expected
                || AuthValidator.unifiedOtpMessage([.otpInvalid, .otpEmpty]) == NSLocalizedString("validation.otpEmpty", comment: ""))
    }

    @Test("email invalid + too long collapse into one message")
    func unifiedEmailMultipleRules() throws {
        // 251 'a's + "@b.c" = 255 chars (>254 → too long) and the single-char
        // TLD "c" makes it invalid — both rules fire at once.
        let local = String(repeating: "a", count: 251)
        let errors = AuthValidator.validateEmail("\(local)@b.c")
        #expect(errors.contains(.emailTooLong))
        #expect(errors.contains(.emailInvalid))
        let msg = AuthValidator.unifiedEmailMessage(errors)
        let message = try #require(msg)
        #expect(message.contains(NSLocalizedString("validation.email.rule.invalid", comment: "")))
        #expect(message.contains(NSLocalizedString("validation.email.rule.tooLong", comment: "")))
    }

    @Test("joinFragments grammar")
    func joinFragments() {
        let and = NSLocalizedString("common.and", comment: "")
        #expect(AuthValidator.joinFragments(["A"]) == "A")
        #expect(AuthValidator.joinFragments(["A", "B"]) == "A \(and) B")
        #expect(AuthValidator.joinFragments(["A", "B", "C"]) == "A, B \(and) C")
    }
}