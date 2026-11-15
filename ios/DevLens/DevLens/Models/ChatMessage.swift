import Foundation

nonisolated enum ChatRole: String, Codable {
    case user
    case assistant
}

nonisolated struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: ChatRole
    let authorID: UUID?
    var text: String
    var sourceChunks: [SourceChunk]
    var statusText: String?
    var isExcludedFromContext: Bool?
    var sequence: Int?

    init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String,
        sourceChunks: [SourceChunk] = [],
        statusText: String? = nil,
        authorID: UUID? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.sourceChunks = sourceChunks
        self.statusText = statusText
        self.authorID = authorID
    }
}
