import Foundation

@MainActor
final class ConversationInvitationViewModel {
    private let service: any ConversationInvitationService

    private(set) var invitations: [IncomingConversationInvitation] = []

    init(service: any ConversationInvitationService) {
        self.service = service
    }

    func load() async throws {
        invitations = try await service.listIncomingConversationInvitations()
    }

    func accept(id: UUID) async throws -> UUID {
        let response = try await service.acceptConversationInvitation(id: id)

        invitations.removeAll { $0.id == id }

        return response.conversationID
    }

    func decline(id: UUID) async throws {
        try await service.declineConversationInvitation(id: id)

        invitations.removeAll { $0.id == id }
    }
}
