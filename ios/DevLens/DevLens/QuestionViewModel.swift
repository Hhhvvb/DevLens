import Foundation

enum QuestionViewState {
    case idle
    case loading
    case success(AskResponse)
    case failure(String)
    
    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        
        return false
    }
}

@MainActor
final class QuestionViewModel {
    
    private let apiClient: any QuestionService
    
    var onStatChanged: (@MainActor (QuestionViewState) -> Void)?
    
    init(apiClient: any QuestionService) {
        self.apiClient = apiClient
    }
    
    private(set) var state: QuestionViewState = .idle {
        didSet {
            onStatChanged?(state)
        }
    }
    
    func submit(_ rawQuestion: String) {
        guard !state.isLoading else {
            return
        }
        
        let question = rawQuestion.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        
        guard !question.isEmpty else {
            state = .failure("请输入问题，不能只输入空格。")
            return
        }
        
        state = .loading
        
        Task { [weak self] in
            guard let self else {
                return
            }
            
            do {
                let response = try await self.apiClient.sendQuestion(
                    question
                )
                
                self.state = .success(response)
            } catch {
                self.state = .failure(
                    "请求失败：\(error.localizedDescription)"
                )
            }
        }
    }
}
