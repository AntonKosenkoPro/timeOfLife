import Vapor
import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver

@main
struct Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        let app = try await Application.make(env)

        app.logger.logLevel = env.isRelease ? .info : .debug

        do {
            try await configure(app)
        } catch {
            app.logger.critical("Boot failed: \(error)")
            try await app.asyncShutdown()
            throw error
        }

        try await app.execute()
    }
}