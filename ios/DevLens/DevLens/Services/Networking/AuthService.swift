import Foundation

@MainActor
protocol AuthService {
    func login(
        _ request: LoginRequest
    ) async throws -> LoginResponse
}
