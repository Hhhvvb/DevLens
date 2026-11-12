import Foundation

@MainActor
final class InviteFriendViewModel {
    private let conversationID: UUID
    private let friendService: any FriendService
    private let invitationService: any ConversationInvitationService

    private(set) var friends: [FriendSummary] = []

    init(
        conversationID: UUID,
        friendService: any FriendService,
        invitationService: any ConversationInvitationService
    ) {
        self.conversationID = conversationID
        self.friendService = friendService
        self.invitationService = invitationService
    }

    func load() async throws {
        friends = try await friendService.listFriends()
    }

    func invite(_ friend: FriendSummary) async throws {
        try await invitationService.sendConversationInvitation(
            conversationID: conversationID,
            recipientID: friend.id
        )
    }
}
