import Foundation

nonisolated struct AskRequest: Encodable {
    let question: String
}

nonisolated struct AskResponse: Decodable {
    let question: String
    let answer: String
    let sources: [String]
    let sourceChunks: [SourceChunk]
}

nonisolated struct StreamDelta: Decodable {
    let text: String
}

nonisolated struct StreamFailture: Decodable {
    let message: String
}

nonisolated struct StreamDone: Decodable {
    let sources: [String]
    let sourceChunks: [SourceChunk]

    enum CodingKeys: String, CodingKey {
        case sources
        case sourceChunks = "source_chunks"
    }
}

nonisolated struct SourceChunk: Decodable {
    let path: String
    let startLine: Int
    let endLine: Int
    let content: String

    enum CodingKeys: String, CodingKey {
        case path
        case startLine = "start_line"
        case endLine = "end_line"
        case content
    }
}
