import Foundation

nonisolated enum AuthSessionState {
    case idle
    case restoring
    case signedOut
    case signedIn(AuthUser)
    case failure(String)
}

@MainActor
final class AuthSession {
    private let service: any AuthService
    private let tokenStore: RefreshTokenStore

    private var isRestoring = false

    private(set) var accessToken: String?
    private(set) var accessTokenExpiresAt: Date?

    var onStateChanged: ((AuthSessionState) -> Void)?

    private(set) var state: AuthSessionState = .idle {
        didSet {
            onStateChanged?(state)
        }
    }

    init(
        service: any AuthService,
        tokenStore: RefreshTokenStore
    ) {
        self.service = service
        self.tokenStore = tokenStore
    }

    func accept(_ response: LoginResponse) async throws {
        let expiresAt = Date().addingTimeInterval(
            TimeInterval(response.expiresIn)
        )

        try await tokenStore.save(response.refreshToken)

        accessToken = response.accessToken
        accessTokenExpiresAt = expiresAt
        state = .signedIn(response.user)
    }

    func signOut() async throws {
        try await tokenStore.delete()

        accessToken = nil
        accessTokenExpiresAt = nil
        state = .signedOut
    }

    func restore() async {
        guard !isRestoring else {
            return
        }

        isRestoring = true
        state = .restoring

        defer {
            isRestoring = false
        }

        do {
            guard let token = try await tokenStore.load() else {
                accessToken = nil
                accessTokenExpiresAt = nil
                state = .signedOut
                return
            }

            let response = try await service.refresh(
                RefreshRequest(refreshToken: token)
            )

            try await accept(response)
        } catch {
            if let apiError = error as? APIError,
               apiError.statusCode == 401 {
                do {
                    try await tokenStore.delete()

                    accessToken = nil
                    accessTokenExpiresAt = nil
                    state = .signedOut
                } catch {
                    state = .failure(error.localizedDescription)
                }
            } else {
                state = .failure(error.localizedDescription)
            }
        }
    }
}
