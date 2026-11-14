import Foundation

nonisolated struct CreateConversationRequest: Encodable {
    let id: UUID
    let title: String
}

nonisolated struct ConversationSummary: Decodable, Identifiable {
    let id: UUID
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let memberCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case memberCount = "member_count"
    }
}

nonisolated struct ConversationUpdateEvent: Decodable {
    let isInitial: Bool
    let revisions: [String: Int]
    let removedConversationIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case isInitial = "is_initial"
        case revisions
        case removedConversationIDs = "removed_conversation_ids"
    }
}

nonisolated struct ConversationMessage: Decodable, Identifiable {
    let id: UUID
    let conversationID: UUID
    let sequence: Int
    let role: ChatRole
    let text: String
    let sourceChunks: [SourceChunk]
    let statusText: String?
    let isExcludedFromContext: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID = "conversation_id"
        case sequence
        case role
        case text
        case sourceChunks = "source_chunks"
        case statusText = "status_text"
        case isExcludedFromContext = "is_excluded_from_context"
        case createdAt = "created_at"
    }
}

extension ConversationMessage {
    func toChatMessage() -> ChatMessage {
        var message = ChatMessage(
            id: id,
            role: role,
            text: text,
            sourceChunks: sourceChunks,
            statusText: statusText
        )

        message.isExcludedFromContext = isExcludedFromContext

        return message
    }
}

nonisolated struct ConversationGenerationRecovery: Decodable {
    let snapshot: GenerationSnapshot
    let request: CreateGenerationRequest
}
