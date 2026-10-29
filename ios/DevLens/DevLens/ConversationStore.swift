import Foundation

nonisolated enum ConversationStoreError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "会话暂时无法保存，请返回列表后重试。"
    }
}

actor ConversationStore {
    private let fileURL: URL

    init() throws {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        fileURL = directory.appendingPathComponent("conversations.json")
    }

    func load() throws -> [Conversation] {
        guard FileManager.default.fileExists(
            atPath: fileURL.path
        ) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(
            [Conversation].self,
            from: data
        )
    }

    func save(_ conversations: [Conversation]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(conversations)

        try data.write(
            to: fileURL,
            options: .atomic
        )
    }

    func upsert(_ conversation: Conversation) throws {
        var conversations = try load()

        if let index = conversations.firstIndex(
            where: { $0.id == conversation.id }
        ) {
            conversations[index] = conversation
        } else {
            conversations.insert(conversation, at: 0)
        }

        try save(conversations)
    }
}
