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
    
    func sendQuestion(_ question: String) async throws -> AskResponse {
        try await Task.sleep(for: .seconds(2))
        
        switch scenario {
        case .success:
            return AskResponse(
                question: question,
                answer: "模拟 AI 回答：可以使用 delegate 模式传递事件，"
                + "并通过 weak 委托属性避免不必要的强引用。"
            )
        case .failure:
            throw URLError(.notConnectedToInternet)
        }
        
    }
}
