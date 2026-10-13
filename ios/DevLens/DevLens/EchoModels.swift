import Foundation

nonisolated struct EchoRequest: Encodable {
    let question: String
}

nonisolated struct EchoResponse: Decodable {
    let question: String
    let message: String
    let questionLength: Int
    
    enum CodingKeys: String, CodingKey {
        case question
        case message
        case questionLength = "question_length"
    }
}
