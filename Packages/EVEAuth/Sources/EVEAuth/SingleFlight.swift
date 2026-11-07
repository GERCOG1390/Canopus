import Foundation

/// One run of an operation at a time: callers arriving while it runs wait for that run and get its result.
/// Refreshing a token uses it (the desktop's `refreshing` map): EVE SSO may replace the refresh token on
/// each use, so a second refresh at the same moment could fail or leave a dead token stored.
@MainActor
final class SingleFlight<T: Sendable> {
    private var running: Task<T, Error>?

    func run(_ operation: @escaping @MainActor () async throws -> T) async throws -> T {
        if let running { return try await running.value }
        let task = Task<T, Error> { @MainActor in try await operation() }
        running = task
        defer { running = nil }
        return try await task.value
    }
}
