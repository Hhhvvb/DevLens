import Foundation

nonisolated struct FriendSummary: Decodable, Identifiable {
    let id: UUID
    let nickname: String
    let friendsSince: Date

    enum CodingKeys: String, CodingKey {
        case id
        case nickname
        case friendsSince = "friends_since"
    }
}

nonisolated struct SendFriendRequest: Encodable {
    let email: String
}

nonisolated struct FriendRequestReceipt: Decodable {
    let message: String
}

nonisolated struct IncomingFriendRequest: Decodable, Identifiable {
    let id: UUID
    let senderID: UUID
    let senderNickname: String
    let senderEmail: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case senderID = "sender_id"
        case senderNickname = "sender_nickname"
        case senderEmail = "sender_email"
        case createdAt = "created_at"
    }
}

nonisolated enum FriendRequestDecision: String {
    case accept
    case decline
}
