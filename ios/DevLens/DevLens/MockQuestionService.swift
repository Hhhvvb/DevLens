import Foundation

@MainActor
final class MockQuestionService: QuestionService {

    enum Scenario {
        case success
        case failure
    }

    private let scenario: Scenario

    init(scenario: Scenario) {
        self.scenario = scenario
    }

    func sendQuestion(
        _ question: String,
        onUpdate: @MainActor (String) -> Void
    ) async throws -> AskResponse {
        switch scenario {
        case .success:
            let parts = [
                "模拟 AI 回答：",
                "delegate 可以用于传递事件。",
                "\n通常使用 weak 委托属性避免不必要的强引用。"
            ]

            var answer = ""

            for part in parts {
                try await Task.sleep(for: .milliseconds(400))
                answer += part
                onUpdate(answer)
            }

            return AskResponse(
                question: question,
                answer: answer
            )

        case .failure:
            throw APIError.networkError(.notConnectedToInternet)
        }
    }
}
