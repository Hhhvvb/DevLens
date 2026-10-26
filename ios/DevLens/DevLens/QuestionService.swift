import Foundation

@MainActor
protocol QuestionService {
    func sendQuestion(
        _ question: String,
        history: [HistoryMessage],
        onUpdate: @MainActor (String) -> Void
    ) async throws -> AskResponse
}
