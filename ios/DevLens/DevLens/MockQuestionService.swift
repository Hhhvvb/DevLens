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
    
    func sendQuestion(_ question: String) async throws -> EchoResponse {
        try await Task.sleep(for: .seconds(2))
        
        switch scenario {
        case .success:
            return EchoResponse(
                question: question,
                message: "模拟回答：收到问题「\(question)」",
                questionLength: question.count
            )
        case .failure:
            throw URLError(.notConnectedToInternet)
        }
        
    }
}
