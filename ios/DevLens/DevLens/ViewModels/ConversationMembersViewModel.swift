import Foundation

@MainActor
final class ConversationMembersViewModel {
    private let service: any ConversationService
    private let conversationID: UUID
    private var nicknames: [UUID: String] = [:]
    private var checkedAuthorIDs: Set<UUID> = []
    private var isLoading = false

    init(service: any ConversationService, conversationID: UUID) {
        self.service = service
        self.conversationID = conversationID
    }

    func nickname(for authorID: UUID?) -> String? {
        guard let authorID else { return nil }
        return nicknames[authorID]
    }

    func loadIfNeeded(for authorIDs: Set<UUID>) async throws -> Bool {
        guard !isLoading, !authorIDs.isSubset(of: checkedAuthorIDs) else {
            return false
        }

        isLoading = true
        defer { isLoading = false }

        let members = try await service.listMembers(conversationID: conversationID)

        nicknames = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.nickname) })

        checkedAuthorIDs.formUnion(authorIDs)
        checkedAuthorIDs.formUnion(nicknames.keys)
        return true
    }
}
