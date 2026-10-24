import Foundation

enum QuestionViewState {
    case idle
    case loading
    case streaming(String)
    case success(AskResponse)
    case failure(answer: String, message: String)
    case cancelled(String)

    var isLoading: Bool {
        switch self {
        case .loading, .streaming(_):
            return true
        default:
            return false
        }
    }
}

@MainActor
final class QuestionViewModel {

    private let apiClient: any QuestionService

    private var requestTask: Task<Void, Never>?

    var onStateChanged: (@MainActor (QuestionViewState) -> Void)?

    init(apiClient: any QuestionService) {
        self.apiClient = apiClient
    }

    private(set) var state: QuestionViewState = .idle {
        didSet {
            onStateChanged?(state)
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
            state = .failure(
                answer: "",
                message: "请输入问题，不能只输入空格。"
            )
            return
        }

        state = .loading

        requestTask = Task { [weak self] in
            guard let self, !Task.isCancelled else {
                return
            }

            defer {
                if !Task.isCancelled {
                    self.requestTask = nil
                }
            }

            var partialAnswer = ""

            do {
                let response = try await self.apiClient.sendQuestion(
                    question
                ) { answer in
                    guard !Task.isCancelled else { return }

                    partialAnswer = answer
                    self.state = .streaming(answer)
                }

                guard !Task.isCancelled else { return }
                self.state = .success(response)
            } catch {
                guard !Task.isCancelled else { return }

                let message = "请求失败：\(error.localizedDescription)"

                self.state = .failure(
                    answer: partialAnswer,
                    message: message
                )
            }
        }
    }

    func cancel() {
        guard state.isLoading else { return }

        let answer: String

        if case .streaming(let text) = state {
            answer = text
        } else {
            answer = ""
        }

        requestTask?.cancel()
        requestTask = nil
        state = .cancelled(answer)
    }
}
