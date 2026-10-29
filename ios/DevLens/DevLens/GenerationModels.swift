import Foundation

nonisolated enum GenerationState: String, Codable {
    case queued
    case running
    case stopRequested = "stop_requested"
    case completed
    case cancelled
    case failed
    case interrupted

    var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .failed, .interrupted:
            return true
        default:
            return false
        }
    }
}

nonisolated struct GenerationSnapshot: Identifiable, Codable {
    let id: UUID
    let conversationID: UUID
    let questionMessageID: UUID
    let answerMessageID: UUID
    let state: GenerationState

    let answer: String
    let revision: Int
    let sourceChunks: [SourceChunk]
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID = "conversation_id"
        case questionMessageID = "question_message_id"
        case answerMessageID = "answer_message_id"
        case state
        case answer
        case revision
        case sourceChunks = "source_chunks"
        case errorMessage = "error_message"
    }
}

nonisolated struct CreateGenerationRequest: Encodable {
    let conversationID: UUID
    let requestID: UUID
    let question: String
    let history: [HistoryMessage]

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case requestID = "request_id"
        case question
        case history
    }
}

nonisolated struct APIErrorResponse: Decodable {
    let detail: String
}
