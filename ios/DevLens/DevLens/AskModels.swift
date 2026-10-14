import Foundation

nonisolated struct AskRequest: Encodable {
    let question: String
}

nonisolated struct AskResponse: Decodable {
    let question: String
    let answer: String
}
