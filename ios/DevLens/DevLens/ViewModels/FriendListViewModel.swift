import Foundation

@MainActor
final class FriendListViewModel {
    private let service: any FriendService
    private(set) var friends: [FriendSummary] = []
    private(set) var incomingRequests: [IncomingFriendRequest] = []

    init(service: any FriendService) {
        self.service = service
    }

    func load() async throws {
        let loadedFriends = try await service.listFriends()
        let loadedRequests = try await service.listIncomingFriendRequests()

        friends = loadedFriends
        incomingRequests = loadedRequests
    }

    func sendFriendRequest(email: String) async throws -> String {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let receipt = try await service.sendFriendRequest(email: trimmedEmail)
        return receipt.message
    }

    func respond(
        to id: UUID,
        decision: FriendRequestDecision
    ) async throws {
        try await service.responseToFriendRequest(
            id: id,
            decision: decision
        )

        incomingRequests.removeAll { $0.id == id }
    }
}
