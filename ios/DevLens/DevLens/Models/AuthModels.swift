import Foundation

nonisolated struct LoginRequest: Encodable {
    let email: String
    let password: String
}

nonisolated struct AuthUser: Decodable, Identifiable {
    let id: UUID
    let email: String
    let nickname: String
}

nonisolated struct LoginResponse: Decodable {
    let user: AuthUser
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case user
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

nonisolated struct RefreshRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}
