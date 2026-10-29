import Foundation

nonisolated enum GenerationViewState {
    case idle
    case connecting
    case receiving(GenerationSnapshot)
    case finished(GenerationSnapshot)
    case connectionFailed(
        snapshot: GenerationSnapshot?,
        message: String
    )
    case submitting
    case submissionFailed(
        request: CreateGenerationRequest,
        message: String
    )

    var isLoading: Bool {
        switch self {
        case .submitting, .connecting, .receiving:
            return true

        case .idle, .finished, .connectionFailed, .submissionFailed:
            return false
        }
    }
}

@MainActor
final class GenerationViewModel {
    private let apiClient: any GenerationService
    private var subscriptionTask: Task<Void, Never>?
    private var subscriptionID = UUID()
    private var stopTask: Task<Void, Never>?
    private var stopRequestID = UUID()

    private(set) var generationID: UUID?
    private(set) var latestSnapshot: GenerationSnapshot?

    var onStateChanged: (@MainActor (GenerationViewState) -> Void)?
    var onStopFailed: (@MainActor (String) -> Void)?

    private(set) var state: GenerationViewState = .idle {
        didSet {
            onStateChanged?(state)
        }
    }

    private(set) var isStopping = false {
        didSet {
            if oldValue != isStopping {
                onStateChanged?(state)
            }
        }
    }

    var canStop: Bool {
        guard let latestSnapshot,
              latestSnapshot.id == generationID else {
            return false
        }

        return !isStopping && (
            latestSnapshot.state == . queued
            || latestSnapshot.state == .running
        )
    }

    init(apiClient: any GenerationService) {
        self.apiClient = apiClient
    }

    func submit(_ request: CreateGenerationRequest) {
        switch state {
        case .submitting, .connecting, .receiving:
            return
        default:
            break
        }

        startOperation(
            id: request.requestID,
            request: request
        )
    }

    func subscribe(to id: UUID) {
        startOperation(
            id: id,
            request: nil
        )
    }

    private func startOperation(
        id: UUID,
        request: CreateGenerationRequest?
    ) {
        disconnect()

        if generationID != id {
            stopRequestID = UUID()
            stopTask?.cancel()
            stopTask = nil
            isStopping = false

            latestSnapshot = nil
        }

        generationID = id
        state = request == nil ? .connecting : .submitting

        let currentSubscriptionID = subscriptionID

        subscriptionTask = Task { [weak self] in
            guard let self else {
                return
            }

            defer {
                if self.subscriptionID == currentSubscriptionID {
                    self.subscriptionTask = nil
                }
            }

            var isCreating = request != nil

            do {
                try Task.checkCancellation()

                if let request {
                    let created = try await self.apiClient.createGeneration(
                        request
                    )

                    try Task.checkCancellation()

                    guard self.subscriptionID == currentSubscriptionID else {
                        return
                    }

                    guard created.id == request.requestID,
                          created.conversationID == request.conversationID else {
                        throw APIError.invalidResponse
                    }

                    isCreating = false
                    self.receive(created)

                    if created.state.isTerminal {
                        return
                    }
                }

                let final = try await self.apiClient.subscribeGeneration(
                    id: id
                ) { snapshot in
                    guard self.subscriptionID == currentSubscriptionID,
                          !Task.isCancelled else {
                        return
                    }

                    self.receive(snapshot)
                }

                try Task.checkCancellation()

                guard self.subscriptionID == currentSubscriptionID else {
                    return
                }

                if self.latestSnapshot?.id != final.id || self.latestSnapshot?.revision != final.revision {
                    self.receive(final)
                }
            } catch is CancellationError {
                // 主动断开订阅，不显示为连接失败。
            } catch {
                guard self.subscriptionID == currentSubscriptionID,
                      !Task.isCancelled else {
                    return
                }

                if isCreating, let request {
                    self.state = .submissionFailed(
                        request: request,
                        message: error.localizedDescription
                    )
                } else {
                    self.state = .connectionFailed(
                        snapshot: self.latestSnapshot,
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    func disconnect() {
        subscriptionID = UUID()
        subscriptionTask?.cancel()
        subscriptionTask = nil
        state = .idle
    }

    private func receive(_ snapshot: GenerationSnapshot) {
        guard snapshot.id == generationID else {
            return
        }

        if let latestSnapshot,
           latestSnapshot.id == snapshot.id,
           snapshot.revision < latestSnapshot.revision {
            return
        }

        latestSnapshot = snapshot

        if snapshot.state.isTerminal {
            state = .finished(snapshot)
        } else {
            state = .receiving(snapshot)
        }
    }

    func stop() {
        guard canStop, let id = generationID else {
            return
        }

        let currentStopRequestID = UUID()
        stopRequestID = currentStopRequestID
        let currentSubscriptionID = subscriptionID
        isStopping = true

        stopTask = Task { [weak self] in
            guard let self else {
                return
            }

            defer {
                if self.stopRequestID == currentStopRequestID {
                    self.stopTask = nil
                    self.isStopping = false
                }
            }

            do {
                let snapshot = try await self.apiClient.stopGeneration(id: id)

                try Task.checkCancellation()

                guard self.stopRequestID == currentStopRequestID,
                      self.subscriptionID == currentSubscriptionID,
                      self.generationID == id else {
                    return
                }

                guard snapshot.id == id else {
                    throw APIError.invalidResponse
                }

                if self.latestSnapshot?.revision != snapshot.revision {
                    self.receive(snapshot)
                }

                if self.subscriptionTask == nil,
                   !snapshot.state.isTerminal {
                    self.subscribe(to: id)
                }
            } catch is CancellationError {
                // 取消本地等待，不显示错误。
            } catch {
                guard self.stopRequestID == currentStopRequestID,
                      self.subscriptionID == currentSubscriptionID,
                      self.generationID == id,
                      !Task.isCancelled else {
                    return
                }

                self.onStopFailed?(error.localizedDescription)
            }
        }
    }
}
