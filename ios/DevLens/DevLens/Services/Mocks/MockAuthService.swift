import Foundation

#if DEBUG

nonisolated enum MockAuthError: LocalizedError {
    case invalidCredentials

    var errorDescription: String? {
        "邮箱或密码不正确。"
    }
}

@MainActor
final class MockAuthService: AuthService {
    enum Scenario {
        case success
        case failure
    }

    private let scenario: Scenario

    init(scenario: Scenario) {
        self.scenario = scenario
    }

    func login(
        _ request: LoginRequest
    ) async throws -> LoginResponse {
        try await Task.sleep(for: .seconds(1))

        switch scenario {
        case .failure:
            throw MockAuthError.invalidCredentials

        case .success:
            return LoginResponse(
                user: AuthUser(
                    id: UUID(),
                    email: request.email,
                    nickname: "预览用户"
                ),
                accessToken: "preview-access-token",
                refreshToken: "preview-refresh-token",
                expiresIn: 900
            )
        }
    }
}

#endif
