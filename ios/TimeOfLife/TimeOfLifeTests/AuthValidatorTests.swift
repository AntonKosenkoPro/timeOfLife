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

    // MARK: Password

    @Test("empty password is invalid")
    func emptyPassword() {
        #expect(AuthValidator.validatePassword("") == [.passwordEmpty])
    }

    @Test("whitespace-only password is rejected")
    func whitespaceOnly() {
        #expect(AuthValidator.validatePassword("        ").contains(.passwordWhitespaceOnly))
    }

    @Test("too-short password")
    func shortPassword() {
        #expect(AuthValidator.validatePassword("ab1").contains(.passwordTooShort))
    }

    @Test("too-long password")
    func longPassword() {
        let pw = String(repeating: "a1", count: 65) // 130 chars
        #expect(AuthValidator.validatePassword(pw).contains(.passwordTooLong))
    }

    @Test("password missing a letter")
    func noLetter() {
        #expect(AuthValidator.validatePassword("12345678").contains(.passwordNoLetter))
    }

    @Test("password missing a digit")
    func noDigit() {
        #expect(AuthValidator.validatePassword("abcdefgh").contains(.passwordNoDigit))
    }

    @Test("valid password passes")
    func validPassword() {
        #expect(AuthValidator.validatePassword("abcd1234").isEmpty)
    }

    @Test("combined validate maps to fields")
    func combinedFields() {
        let r = AuthValidator.validate(email: "bad", password: "short1")
        #expect(r[.email]?.contains(.emailInvalid) == true)
        #expect(r[.password]?.contains(.passwordTooShort) == true)
    }

    @Test("combined validate with nil password only checks email")
    func combinedEmailOnly() {
        let r = AuthValidator.validate(email: "", password: nil)
        #expect(r[.email]?.contains(.emailEmpty) == true)
        #expect(r[.password] == nil)
    }
}