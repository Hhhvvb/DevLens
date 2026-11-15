import Foundation

nonisolated struct IncomingConversationInvitation: Decodable, Identifiable {
    let id: UUID
    let conversationTitle: String
    let inviterNickname: String
    let createdAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case conversationTitle = "conversation_title"
        case inviterNickname = "inviter_nickname"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

nonisolated struct CreateConversationInvitationRequest: Encodable {
    let recipientID: UUID

    enum CodingKeys: String, CodingKey {
        case recipientID = "recipient_id"
    }
}

nonisolated struct AcceptConversationInvitationResponse: Decodable {
    let conversationID: UUID

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
    }
}
