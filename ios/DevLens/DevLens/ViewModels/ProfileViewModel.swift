import Foundation

struct ProfileViewModel {
    let nickname: String
    let email: String
    let avatarText: String
    private(set) var avatarData: Data?

    init(user: AuthUser) {
        nickname = user.nickname
        email = user.email
        avatarText = user.nickname.first.map { String($0) } ?? "?"
    }

    mutating func setAvatarData(_ data: Data) {
        avatarData = data
    }
}
