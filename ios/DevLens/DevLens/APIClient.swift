import Foundation

nonisolated enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case networkError(URLError.Code)
    case streamError(String)
    case incompleteStream

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "服务地址配置有误。"
        case .invalidResponse:
            return "服务器返回了无法识别的响应。"
        case .httpError(let statusCode):
            switch statusCode {
            case 422:
                return "问题未通过校验，最长支持 3000 个字符。"
            case 502:
                return "AI 服务暂时不可用，请稍后重试。"
            case 503:
                return "服务器尚未配置 AI 服务。"
            case 504:
                return "AI 回答超时，请稍后重试。"
            default:
                return "服务器请求失败，状态码：\(statusCode)"
            }
        case .networkError(let code):
            switch code {
            case .timedOut:
                return "请求超时，请检查服务连接后重试。"
            case .notConnectedToInternet:
                return "当前网络不可用，请检查网络连接。"
            case .cannotConnectToHost, .cannotFindHost:
                return "无法连接 DevLens 服务，请检查后端是否启动及服务地址。"
            case .networkConnectionLost:
                return "网络连接已中断，请重新提交。"
            default:
                return "网络请求失败，请稍后重试。"
            }
        case .streamError(let message):
            return message
        case .incompleteStream:
            return "回答尚未完成，连接已结束，请重新提交。"
        }
    }
}

@MainActor
final class APIClient: QuestionService {
    #if targetEnvironment(simulator)
    private let baseURL = "http://127.0.0.1:8000"
    #else
    private let baseURL = "http://172.20.10.10:8000"
    #endif

    func sendQuestion(
        _ question: String,
        history: [HistoryMessage],
        onUpdate: @MainActor (String) -> Void
    ) async throws -> AskResponse {
        guard let url = URL(string: "\(baseURL)/v1/ask/stream") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            "text/event-stream",
            forHTTPHeaderField: "Accept"
        )
        request.httpBody = try JSONEncoder().encode(
            AskRequest(question: question, history: history)
        )

        do {
            let (bytes, response) = try await URLSession.shared.bytes(
                for: request
            )
            defer { bytes.task.cancel() }

            guard let http = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard (200..<300).contains(http.statusCode) else {
                throw APIError.httpError(http.statusCode)
            }

            guard http.mimeType?.lowercased() == "text/event-stream" else {
                throw APIError.invalidResponse
            }

            var event = ""
            var answer = ""
            let decoder = JSONDecoder()

            for try await line in bytes.lines {
                try Task.checkCancellation()

                if line.hasPrefix("event:") {
                    event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    let data = Data(line.dropFirst(5).utf8)

                    switch event {
                    case "delta":
                        let delta = try decoder.decode(
                            StreamDelta.self,
                            from: data
                        )
                        answer += delta.text
                        onUpdate(answer)

                    case "done":
                        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            throw APIError.invalidResponse
                        }

                        let done = try decoder.decode(
                            StreamDone.self,
                            from: data
                        )

                        return AskResponse(
                            question: question,
                            answer: answer,
                            sources: done.sources,
                            sourceChunks: done.sourceChunks
                        )

                    case "error":
                        let failure = try decoder.decode(
                            StreamFailture.self,
                            from: data
                        )
                        throw APIError.streamError(failure.message)

                    default:
                        throw APIError.invalidResponse
                    }

                    event = ""
                }
            }

            throw APIError.incompleteStream
        } catch let error as URLError {
            throw APIError.networkError(error.code)
        } catch is DecodingError {
            throw APIError.invalidResponse
        }
    }
}
