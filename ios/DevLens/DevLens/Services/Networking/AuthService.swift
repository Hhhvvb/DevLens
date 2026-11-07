import Foundation

@MainActor
protocol AuthService {
    func login(
        _ request: LoginRequest
    ) async throws -> LoginResponse

    func refresh(
        _ request: RefreshRequest
    ) async throws -> LoginResponse
}
