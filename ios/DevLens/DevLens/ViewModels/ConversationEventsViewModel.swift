import Foundation

@MainActor
final class ConversationEventsViewModel {
    private let service: any ConversationService
    private var subscriptionTask: Task<Void, Never>?

    var onUpdate: ((ConversationUpdateEvent) -> Void)?

    init(service: any ConversationService) {
        self.service = service
    }

    func start() {
        guard subscriptionTask == nil else { return }

        let service = self.service

        subscriptionTask = Task { [weak self] in
            defer {
                if !Task.isCancelled {
                    self?.subscriptionTask = nil
                }
            }

            while !Task.isCancelled, self != nil {
                do {
                    try await service.subscribeConversationEvents { [weak self] update in
                        guard !Task.isCancelled else { return }
                        self?.onUpdate?(update)
                    }
                } catch is CancellationError {
                    return
                } catch let error as APIError where error.statusCode == 401 || error.statusCode == 403 {
                    return
                } catch {
                    // 连接意外中断，稍后重连。
                }

                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }
}
