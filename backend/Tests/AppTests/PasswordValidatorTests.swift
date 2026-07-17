import XCTest
@testable import App

final class PasswordValidatorTests: XCTestCase {

    func testValidPasswords() {
        XCTAssert(PasswordValidator.violations("Abcdef12").isEmpty)
        XCTAssert(PasswordValidator.violations("longP@ss1word").isEmpty)
        XCTAssert(PasswordValidator.violations("a1b2c3d4e5").isEmpty)
        XCTAssert(PasswordValidator.violations("Z9zzzzzz").isEmpty)
    }

    func testTooShort() {
        let v = PasswordValidator.violations("Ab1")
        XCTAssertTrue(v.contains(PasswordValidator.Rule.minLength.rawValue))
    }

    func testMissingLetter() {
        let v = PasswordValidator.violations("12345678")
        XCTAssertTrue(v.contains(PasswordValidator.Rule.atLeastOneLetter.rawValue))
    }

    func testMissingDigit() {
        let v = PasswordValidator.violations("abcdefgh")
        XCTAssertTrue(v.contains(PasswordValidator.Rule.atLeastOneDigit.rawValue))
    }

    func testWhitespaceOnly() {
        let v = PasswordValidator.violations("   ")
        XCTAssertTrue(v.contains(PasswordValidator.Rule.noWhitespaceOnly.rawValue))
    }

    func testMaxLengthBoundary() {
        // 128 chars with letter+digit: valid.
        let pw = String(repeating: "a", count: 127) + "1"
        XCTAssertEqual(pw.count, 128)
        XCTAssertTrue(PasswordValidator.violations(pw).isEmpty)

        // 129 chars: too long.
        let tooLong = String(repeating: "a", count: 128) + "1"
        XCTAssertEqual(tooLong.count, 129)
        let v = PasswordValidator.violations(tooLong)
        XCTAssertTrue(v.contains(PasswordValidator.Rule.maxLength.rawValue))
    }

    func testValidateOrThrow() {
        XCTAssertNoThrow(try PasswordValidator.validateOrThrow("Abcdef12"))
        XCTAssertThrowsError(try PasswordValidator.validateOrThrow("abc")) { error in
            guard case AuthError.weakPassword(let rules) = error else {
                XCTFail("expected weakPassword"); return
            }
            XCTAssertFalse(rules.isEmpty)
        }
    }
}