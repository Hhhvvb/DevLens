import Foundation

nonisolated enum ChatRole {
    case user
    case assistant
}

nonisolated struct ChatMessage: Identifiable {
    let id: UUID
    let role: ChatRole
    var text: String

    init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String
    ) {
        self.id = id
        self.role = role
        self.text = text
    }
}
