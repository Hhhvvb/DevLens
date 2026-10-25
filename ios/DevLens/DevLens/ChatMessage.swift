import Foundation

nonisolated enum ChatRole: String, Codable {
    case user
    case assistant
}

nonisolated struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: ChatRole
    var text: String
    var sourceChunks: [SourceChunk]
    var statusText: String?

    init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String,
        sourceChunks: [SourceChunk] = [],
        statusText: String? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.sourceChunks = sourceChunks
        self.statusText = statusText
    }
}
