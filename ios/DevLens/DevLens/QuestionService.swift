import Foundation

@MainActor
protocol QuestionService {
    func sendQuestion(_ question: String) async throws -> AskResponse
}
