import Foundation

nonisolated struct ActiveGeneration: Codable {
    let request: CreateGenerationRequest
    var questionMessageID: UUID
    var answerMessageID: UUID
    var isConfirmed = false

    var generationID: UUID {
        request.requestID
    }
}
