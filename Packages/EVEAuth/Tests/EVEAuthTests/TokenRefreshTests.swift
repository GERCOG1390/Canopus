import Foundation
import Testing
@testable import EVEAuth

/// Refreshing a character's token: EVE SSO may replace the refresh token on each use, so two refreshes at
/// once can leave the app holding a dead one ("invalid_grant") and the pilot signed out.
@Suite("Token refresh")
@MainActor
struct TokenRefreshTests {
    @Test func parallelCallersShareOneRefresh() async throws {
        let flight = SingleFlight<Int>()
        var runs = 0
        let op: @MainActor () async throws -> Int = {
            runs += 1
            try await Task.sleep(for: .milliseconds(30))
            return runs
        }
        async let a = flight.run(op)
        async let b = flight.run(op)
        async let c = flight.run(op)
        let results = try await [a, b, c]
        #expect(runs == 1)
        #expect(results == [1, 1, 1])
        // Finished: the next refresh is a new one.
        #expect(try await flight.run(op) == 2)
    }

    @Test func aFailureReachesEveryoneAndClears() async throws {
        let flight = SingleFlight<Int>()
        await #expect(throws: URLError.self) { try await flight.run { throw URLError(.timedOut) } }
        #expect(try await flight.run { 7 } == 7)
    }

    @Test func deadRefreshTokenMeansSignInAgain() {
        let body = #"{"error":"invalid_grant","error_description":"Invalid refresh token. Unable to migrate grant."}"#
        #expect(AuthError.httpError(400, body).isDeadRefreshToken)
        // Temporary trouble must not sign anyone out.
        #expect(!AuthError.httpError(500, "Internal error").isDeadRefreshToken)
        #expect(!AuthError.httpError(503, nil).isDeadRefreshToken)
        #expect(!AuthError.networkError(URLError(.notConnectedToInternet)).isDeadRefreshToken)
    }

    /// EVE's tokens are base64: an unescaped "+" reaches the server as a space and the token is "invalid".
    @Test func formBodyEscapesTokens() throws {
        let body = EVEAuthClient.formBody(["refresh_token": "ab+cd/ef==", "grant_type": "refresh_token", "redirect": "eveauth-canopus://callback"])
        let text = try #require(String(data: body, encoding: .utf8))
        #expect(text == "grant_type=refresh_token&redirect=eveauth-canopus%3A%2F%2Fcallback&refresh_token=ab%2Bcd%2Fef%3D%3D")
    }

    /// Every path that refreshes goes through the single flight: one call to the client in the service.
    @Test func serviceRefreshesInOnePlace() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/EVEAuth/CharacterService.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        #expect(text.components(separatedBy: "authClient.refresh(").count - 1 == 1)
    }
}
