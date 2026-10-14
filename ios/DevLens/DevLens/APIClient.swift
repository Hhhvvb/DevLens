import Foundation

nonisolated enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case networkError(URLError.Code)
    
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
        }
    }
}

@MainActor
final class APIClient: QuestionService {
    #if targetEnvironment(simulator)
    private let baseURL = "http://127.0.0.1:8000"
    #else
    private let baseURL = "http://10.22.154.234:8000"
    #endif
    
    func sendQuestion(_ question: String) async throws -> AskResponse {
        guard let url = URL(string: "\(baseURL)/v1/ask") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        
        let payload = AskRequest(question: question)
        request.httpBody = try JSONEncoder().encode(payload)
        
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw APIError.networkError(error.code)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        do {
            return try JSONDecoder().decode(
                AskResponse.self,
                from: data
            )
        } catch {
            throw APIError.invalidResponse
        }
    }
}
