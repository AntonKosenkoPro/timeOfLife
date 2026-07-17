import Foundation
import AsyncHTTPClient
import Vapor

/// Which localized email to render.
enum EmailTemplateKey: String, Sendable {
    case verifyEmail = "verify_email"
    case passwordReset = "password_reset"
}

/// Two-letter language. Default `en` when Accept-Language absent/unmapped.
enum EmailLanguage: String, Sendable {
    case en
    case ru

    static func from(acceptLanguage header: String?) -> EmailLanguage {
        guard let header, !header.isEmpty else { return .en }
        // Parse comma-separated tags, take the first that matches.
        let first = header.split(separator: ",").first.map { String($0) }
        guard let first else { return .en }
        let tag = first.split(separator: "-").first.map { String($0).lowercased() } ?? "en"
        return EmailLanguage(rawValue: tag) ?? .en
    }
}

/// Protocol so tests/production can swap implementations. Console in dev, Mailgun in prod.
protocol EmailSender: Sendable {
    func send(to address: String, subjectKey: EmailTemplateKey, language: EmailLanguage, linkURL: String) async throws
}

/// Localized subject + body for a template, given a target link URL.
enum EmailContent {
    static func subject(for key: EmailTemplateKey, language: EmailLanguage) -> String {
        switch (key, language) {
        case (.verifyEmail, .en): return "Verify your Time of Life account"
        case (.verifyEmail, .ru): return "Подтвердите ваш аккаунт Time of Life"
        case (.passwordReset, .en): return "Reset your Time of Life password"
        case (.passwordReset, .ru): return "Сброс пароля Time of Life"
        }
    }

    static func body(for key: EmailTemplateKey, language: EmailLanguage, linkURL: String) -> String {
        switch (key, language) {
        case (.verifyEmail, .en):
            return """
            Welcome to Time of Life.
            Verify your email by opening this link:
            \(linkURL)
            If you did not create an account, you can ignore this email.
            """
        case (.verifyEmail, .ru):
            return """
            Добро пожаловать в Time of Life.
            Подтвердите ваш email, открыв эту ссылку:
            \(linkURL)
            Если вы не создавали аккаунт, проигнорируйте это письмо.
            """
        case (.passwordReset, .en):
            return """
            We received a request to reset your Time of Life password.
            Reset it by opening this link:
            \(linkURL)
            If you did not request a reset, ignore this email — your password will not change.
            """
        case (.passwordReset, .ru):
            return """
            Мы получили запрос на сброс пароля Time of Life.
            Сбросьте пароль, открыв эту ссылку:
            \(linkURL)
            Если вы не запрашивали сброс, проигнорируйте это письмо — пароль не изменится.
            """
        }
    }
}

/// Prints the email to stdout (dev). Only the reset/verify link line is printed to avoid leaking PII.
final class ConsoleEmailSender: EmailSender {
    let logger: Logger

    init(logger: Logger = Logger(label: "email.console")) {
        self.logger = logger
    }

    func send(to address: String, subjectKey: EmailTemplateKey, language: EmailLanguage, linkURL: String) async throws {
        let subject = EmailContent.subject(for: subjectKey, language: language)
        // We deliberately only print the link (and a short prefix) — never the recipient address,
        // to avoid leaking email addresses in logs.
        print("[email:\(subjectKey.rawValue)] subject=\"\(subject)\" lang=\(language.rawValue) link=\(linkURL)")
        logger.info("email.console sent subject=\(subjectKey.rawValue) lang=\(language.rawValue) link=\(linkURL)")
    }
}

/// Sends via Mailgun HTTP API using AsyncHTTPClient.
final class MailgunEmailSender: EmailSender {
    let httpClient: HTTPClient
    let config: AppConfig.MailgunConfig

    init(httpClient: HTTPClient, config: AppConfig.MailgunConfig) {
        self.httpClient = httpClient
        self.config = config
    }

    func send(to address: String, subjectKey: EmailTemplateKey, language: EmailLanguage, linkURL: String) async throws {
        let subject = EmailContent.subject(for: subjectKey, language: language)
        let body = EmailContent.body(for: subjectKey, language: language, linkURL: linkURL)

        let url = "\(config.apiBaseURL)/v3/\(config.domain)/messages"
        let auth = "api:\(config.apiKey)"
        let authHeader = "Basic " + Data(auth.utf8).base64EncodedString()

        var headers = HTTPHeaders([("Authorization", authHeader)])
        headers.add(name: "Content-Type", value: "application/x-www-form-urlencoded")

        let fields: [String: String] = [
            "from": config.from,
            "to": address,
            "subject": subject,
            "text": body
        ]
        let bodyString = fields
            .map { "\($0.key)=\(Self.urlEncode($0.value))" }
            .joined(separator: "&")

        var request = HTTPClientRequest(url: url)
        request.method = .POST
        request.headers = headers
        request.body = .bytes(ByteBuffer(string: bodyString))

        let response = try await httpClient.execute(request, timeout: .seconds(20))
        guard (200..<300).contains(Int(response.status.code)) else {
            throw MailgunError(statusCode: Int(response.status.code))
        }
    }

    static func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    struct MailgunError: Error { let statusCode: Int }
}