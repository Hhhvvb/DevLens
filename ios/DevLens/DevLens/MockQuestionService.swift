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
                "## 取消请求\n\n",
                "取消是 **协作式",
                "的**，需要主动检查状态。\n\n",
                "```swift\n",
                "guard !Task.isCancelled else {\n",
                "    return\n",
                "}\n",
                "```\n\n",
                "> 检查应放在更新界面之前。\n\n",
                "- 保留已经生成的内容。\n",
                "- 阻止旧任务继续更新状态。\n\n",
                "回答结束。"
            ]

            var answer = ""

            for part in parts {
                try await Task.sleep(for: .milliseconds(400))
                answer += part
                onUpdate(answer)
            }

            return AskResponse(
                question: question,
                answer: answer,
                sources: [],
                sourceChunks: []

            )

        case .failure:
            throw APIError.networkError(.notConnectedToInternet)
        }
    }
}
