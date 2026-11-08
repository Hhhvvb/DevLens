import Foundation

@MainActor
protocol FriendService {
    func listFriends() async throws -> [FriendSummary]
    func sendFriendRequest(email: String) async throws -> FriendRequestReceipt
    func listIncomingFriendRequests() async throws -> [IncomingFriendRequest]
}
