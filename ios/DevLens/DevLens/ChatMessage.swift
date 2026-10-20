import Foundation

nonisolated enum ChatRole {
    case user
    case assistant
}

nonisolated struct ChatMessage: Identifiable {
    let id: UUID
    let role: ChatRole
    var text: String
    var sourceChunks: [SourceChunk]

    init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String,
        sourceChunks: [SourceChunk] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.sourceChunks = sourceChunks
    }
}
