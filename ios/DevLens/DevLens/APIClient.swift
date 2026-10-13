import Foundation

nonisolated enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "服务地址配置有误。"
        case .invalidResponse:
            return "服务器返回了无法识别的响应。"
        case .httpError(let statusCode):
            if statusCode == 422 {
                return "问题未通过校验，请检查内容，最长支持 3000 个字符。"
            }
            
            return "服务器请求失败，状态码：\(statusCode)"
        }
    }
}

@MainActor
final class APIClient {
    private let baseURL = "http://127.0.0.1:8000"
    
    func sendQuestion(_ question: String) async throws -> EchoResponse {
        guard let url = URL(string: "\(baseURL)/v1/echo") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        
        let payload = EchoRequest(question: question)
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response) = try await URLSession.shared.data(
            for: request
        )
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(
            EchoResponse.self,
            from: data
        )
    }
}
