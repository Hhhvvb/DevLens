import Foundation

@MainActor
protocol ConversationInvitationService {
    func sendConversationInvitation(
        conversationID: UUID,
        recipientID: UUID
    ) async throws

    func listIncomingConversationInvitations()
        async throws -> [IncomingConversationInvitation]

    func acceptConversationInvitation(
        id: UUID
    ) async throws -> AcceptConversationInvitationResponse

    func declineConversationInvitation(
        id: UUID
    ) async throws
}
