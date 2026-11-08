import Foundation

nonisolated enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case networkError(URLError.Code)
    case streamError(String)
    case incompleteStream
    case serverError(String)
    case subscriptionInterrupted
    case httpFailure(statusCode: Int, message: String)

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
                return "网络连接已中断，请检查连接后重试。"
            default:
                return "网络请求失败，请稍后重试。"
            }
        case .streamError(let message):
            return message
        case .incompleteStream:
            return "回答尚未完成，连接已结束，请重新提交。"
        case .serverError(let message):
            return message
        case .subscriptionInterrupted:
            return "订阅连接已结束，任务可能仍在生成，请重新连接查看。"
        case .httpFailure(_, let message):
            return message
        }
    }

    var statusCode: Int? {
        switch self {
        case .httpError(let code):
            return code

        case .httpFailure(let code, _):
            return code

        default:
            return nil
        }
    }
}

@MainActor
final class APIClient:
    QuestionService,
    GenerationService,
    ConversationService,
    AuthService,
    ProfileService,
    FriendService {
    #if targetEnvironment(simulator)
    private let baseURL = "http://127.0.0.1:8000"
    #else
    private let baseURL = "http://172.20.10.10:8000"
    #endif

    private let accessTokenProvider: @MainActor () -> String?

    init(
        accessTokenProvider: @escaping @MainActor () -> String? = { nil }
    ) {
        self.accessTokenProvider = accessTokenProvider
    }

    func createGeneration(
        _ input: CreateGenerationRequest
    ) async throws -> GenerationSnapshot {
        guard let accessToken = accessTokenProvider() else {
            throw APIError.httpFailure(
                statusCode: 401,
                message: "请先登录。"
            )
        }

        let body = try JSONEncoder().encode(input)

        return try await sendJSONRequest(
            path: "/v1/generations",
            method: "POST",
            body: body,
            accessToken: accessToken
        )
    }

    private func requireAccessToken() throws -> String {
        guard let accessToken = accessTokenProvider() else {
            throw APIError.httpFailure(
                statusCode: 401,
                message: "请先登录。"
            )
        }

        return accessToken
    }

    func getGeneration(
        id: UUID
    ) async throws -> GenerationSnapshot {
        return try await sendJSONRequest(
            path: "/v1/generations/\(id.uuidString)",
            method: "GET",
            accessToken: requireAccessToken()
        )
    }

    func stopGeneration(
        id: UUID
    ) async throws -> GenerationSnapshot {
        return try await sendJSONRequest(
            path: "/v1/generations/\(id.uuidString)/stop",
            method: "POST",
            accessToken: requireAccessToken()
        )
    }

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

    private func sendJSONRequest<Response: Decodable>(
        path: String,
        method: String,
        body: Data? = nil,
        accessToken: String? = nil
    ) async throws -> Response {
        guard let url = URL(
            string: "\(baseURL)\(path)"
        ) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 20

        if let accessToken {
            request.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "Authorization"
            )
        }

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        if body != nil {
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )
        }

        do {
            let (data, response) = try await URLSession.shared.data(
                for: request
            )

            try Task.checkCancellation()

            guard let http = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard (200..<300).contains(http.statusCode) else {
                let failure = try? JSONDecoder().decode(
                    APIErrorResponse.self,
                    from: data
                )

                let message: String

                if let detail = failure?.detail,
                   !detail.isEmpty {
                    message = detail
                } else if http.statusCode == 422 {
                    message = "输入未通过校验，请检查字段内容及长度。"
                } else {
                    message = "服务器请求失败，状态码：\(http.statusCode)"
                }

                throw APIError.httpFailure(
                    statusCode: http.statusCode,
                    message: message
                )
            }

            guard http.mimeType?.lowercased() == "application/json" else {
                throw APIError.invalidResponse
            }

            return try makeJSONDecoder().decode(
                Response.self,
                from: data
            )
        } catch let error as URLError {
            if Task.isCancelled {
                throw CancellationError()
            }

            throw APIError.networkError(error.code)
        } catch is DecodingError {
            throw APIError.invalidResponse
        }
    }

    func subscribeGeneration(
        id: UUID,
        onUpdate: @MainActor (GenerationSnapshot) -> Void
    ) async throws -> GenerationSnapshot {
        guard let url = URL(
            string: "\(baseURL)/v1/generations/\(id.uuidString)/events"
        ) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60

        let accessToken = try requireAccessToken()

        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )

        request.setValue(
            "text/event-stream",
            forHTTPHeaderField: "Accept"
        )
        do {
            let (bytes, response) = try await URLSession.shared.bytes(
                for: request
            )

            defer { bytes.task.cancel() }

            try Task.checkCancellation()

            guard let http = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard (200..<300).contains(http.statusCode) else {
                throw APIError.httpError(http.statusCode)
            }

            guard http.mimeType?.lowercased() == "text/event-stream" else {
                throw APIError.invalidResponse
            }

            var parser = SSEParser()
            var lastRevision = -1
            let decoder = JSONDecoder()

            for try await byte in bytes {
                try Task.checkCancellation()

                guard let event = parser.append(byte) else {
                    continue
                }

                let data = Data(event.data.utf8)

                switch event.name {
                case "snapshot":
                    let snapshot = try decoder.decode(
                        GenerationSnapshot.self,
                        from: data
                    )

                    guard snapshot.id == id,
                          snapshot.revision >= 0 else {
                        throw APIError.invalidResponse
                    }

                    guard snapshot.revision > lastRevision else {
                        continue
                    }

                    lastRevision = snapshot.revision
                    onUpdate(snapshot)

                    if snapshot.state.isTerminal {
                        return snapshot
                    }

                case "error":
                    let failture = try decoder.decode(
                        StreamFailture.self,
                        from: data
                    )

                    throw APIError.streamError(failture.message)

                default:
                    continue
                }
            }

            try Task.checkCancellation()
            throw APIError.subscriptionInterrupted
        } catch let error as URLError {
            if Task.isCancelled {
                throw CancellationError()
            }

            throw APIError.networkError(error.code)
        } catch is DecodingError {
            throw APIError.invalidResponse
        }

    }

    private func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds
            ]

            if let date = formatter.date(from: value) {
                return date
            }

            formatter.formatOptions = [
                .withInternetDateTime
            ]

            if let date = formatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "无法解析服务器时间：\(value)"
            )
        }

        return decoder
    }

    func createConversation(
        _ input: CreateConversationRequest
    ) async throws -> ConversationSummary {
        guard let accessToken = accessTokenProvider() else {
            throw APIError.httpFailure(
                statusCode: 401,
                message: "请先登录。"
            )
        }

        let body = try JSONEncoder().encode(input)

        return try await sendJSONRequest(
            path: "/v1/conversations",
            method: "POST",
            body: body,
            accessToken: accessToken
        )
    }

    func listConversations() async throws -> [ConversationSummary] {
        guard let accessToken = accessTokenProvider() else {
            throw APIError.httpFailure(
                statusCode: 401,
                message: "请先登录。"
            )
        }

        return try await sendJSONRequest(
            path: "/v1/conversations",
            method: "GET",
            accessToken: accessToken
        )
    }

    func listMessages(
        conversationID: UUID
    ) async throws -> [ConversationMessage] {
        guard let accessToken = accessTokenProvider() else {
            throw APIError.httpFailure(
                statusCode: 401,
                message: "请先登录。",
            )
        }

        return try await sendJSONRequest(
            path: "/v1/conversations/\(conversationID.uuidString)/messages",
            method: "GET",
            accessToken: accessToken
        )
    }

    func getActiveGeneration(
        conversationID: UUID
    ) async throws -> ConversationGenerationRecovery? {
        guard let accessToken = accessTokenProvider() else {
            throw APIError.httpFailure(
                statusCode: 401,
                message: "请先登录。"
            )
        }

        return try await sendJSONRequest(
            path: "/v1/conversations/\(conversationID.uuidString)/active-generation",
            method: "GET",
            accessToken: accessToken
        )
    }

    func login(
        _ request: LoginRequest
    ) async throws -> LoginResponse {
        let body = try JSONEncoder().encode(request)

        let response: LoginResponse = try await sendJSONRequest(
            path: "/v1/auth/login",
            method: "POST",
            body: body
        )

        guard !response.accessToken.isEmpty,
              !response.refreshToken.isEmpty,
              response.expiresIn > 0 else {
            throw APIError.invalidResponse
        }

        return response
    }

    func refresh(
        _ request: RefreshRequest
    ) async throws -> LoginResponse {
        let body = try JSONEncoder().encode(request)

        let response: LoginResponse = try await sendJSONRequest(
            path: "/v1/auth/refresh",
            method: "POST",
            body: body
        )

        guard !response.accessToken.isEmpty,
              !response.refreshToken.isEmpty,
              response.expiresIn > 0 else {
            throw APIError.invalidResponse
        }

        return response
    }

    func loadMyAvatar() async throws -> Data? {
        let (data, response) = try await sendAvatarRequest(method: "GET")

        if response.statusCode == 404 {
            return nil
        }

        guard response.statusCode == 200,
              response.mimeType == "image/jpeg",
              !data.isEmpty else {
            throw APIError.invalidResponse
        }

        return data
    }

    func uploadMyAvatar(_ jpegData: Data) async throws {
        let (_, response) = try await sendAvatarRequest(
            method: "PUT",
            jpegData: jpegData
        )

        guard response.statusCode == 204 else {
            throw APIError.invalidResponse
        }
    }

    private func sendAvatarRequest(
        method: String,
        jpegData: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: "\(baseURL)/v1/auth/me/avatar") else {
            throw APIError.invalidURL
        }

        let accessToken = try requireAccessToken()

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )

        if let jpegData {
            request.httpBody = jpegData
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        } else {
            request.setValue("image/jpeg", forHTTPHeaderField: "Accept")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()

            guard let http = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            if method == "GET", http.statusCode == 404 {
                return (data, http)
            }

            guard (200..<300).contains(http.statusCode) else {
                let failure = try? JSONDecoder().decode(
                    APIErrorResponse.self,
                    from: data
                )

                throw APIError.httpFailure(
                    statusCode: http.statusCode,
                    message: failure?.detail ?? "头像请求失败，状态码：\(http.statusCode)"
                )
            }

            return (data, http)
        }
    }

    func listFriends() async throws -> [FriendSummary] {
        return try await sendJSONRequest(
            path: "/v1/friends",
            method: "GET",
            accessToken: requireAccessToken()
        )
    }

    func listIncomingFriendRequests() async throws -> [IncomingFriendRequest] {
        return try await sendJSONRequest(
            path: "/v1/friend-requests/incoming",
            method: "GET",
            accessToken: requireAccessToken()
        )
    }

    func sendFriendRequest(
        email: String
    ) async throws -> FriendRequestReceipt {
        let input = SendFriendRequest(email: email)
        let body = try JSONEncoder().encode(input)

        return try await sendJSONRequest(
            path: "/v1/friend-requests",
            method: "POST",
            body: body,
            accessToken: requireAccessToken()
        )
    }

    func responseToFriendRequest(
        id: UUID,
        decision: FriendRequestDecision
    ) async throws {
        let path = "/v1/friend-requests/\(id.uuidString)/\(decision.rawValue)"

        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        let accessToken = try requireAccessToken()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()

            guard let http = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard http.statusCode == 204 else {
                let failure = try? JSONDecoder().decode(
                    APIErrorResponse.self,
                    from: data
                )

                throw APIError.httpFailure(
                    statusCode: http.statusCode,
                    message: failure?.detail ?? "无法处理好友申请。"
                )
            }
        } catch let error as URLError {
            if Task.isCancelled {
                throw CancellationError()
            }

            throw APIError.networkError(error.code)
        }
    }
}
