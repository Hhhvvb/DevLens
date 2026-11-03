import Foundation

nonisolated struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]
    var activeGeneration: ActiveGeneration?

    init(
        id: UUID = UUID(),
        title: String = "新会话",
        createdAt: Date = Date(),
        messages: [ChatMessage] = [],
        activeGeneration: ActiveGeneration? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.messages = messages
        self.activeGeneration = activeGeneration
    }
}
