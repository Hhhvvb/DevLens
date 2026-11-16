import Foundation

#if DEBUG

nonisolated enum MockAuthError: LocalizedError {
    case invalidCredentials
    case registrationFailed

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "邮箱或密码不正确。"
        case .registrationFailed:
            return "注册或邮箱验证失败。"
        }
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

    func register(_ request: RegisterRequest) async throws -> RegisterResponse {
        guard case .success = scenario else {
            throw MockAuthError.registrationFailed
        }

        return RegisterResponse(message: "请查收邮箱验证邮件。")
    }

    func verifyEmail(_ request: VerifyEmailRequest) async throws -> VerifyEmailResponse {
        guard case .success = scenario else {
            throw MockAuthError.registrationFailed
        }

        return VerifyEmailResponse(message: "邮箱验证成功。")
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

    func refresh(
        _ request: RefreshRequest
    ) async throws -> LoginResponse {
        try await Task.sleep(for: .seconds(1))

        switch scenario {
        case .failure:
            throw MockAuthError.invalidCredentials

        case .success:
            return LoginResponse(
                user: AuthUser(
                    id: UUID(),
                    email: "preview@example.com",
                    nickname: "预览用户"
                ),
                accessToken: "preview-new-access-token",
                refreshToken: "preview-new-refresh-token",
                expiresIn: 900
            )
        }
    }
}

#endif
