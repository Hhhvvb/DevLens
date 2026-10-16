import Foundation

@MainActor
protocol QuestionService {
    func sendQuestion(
        _ question: String,
        onUpdate: @MainActor (String) -> Void
    ) async throws -> AskResponse
}
