import Foundation

@MainActor
protocol ConversationService {
    func createConversation(
        _ input: CreateConversationRequest
    ) async throws -> ConversationSummary

    func listConversations() async throws -> [ConversationSummary]

    func listMessages(
        conversationID: UUID
    ) async throws -> [ConversationMessage]

    func getActiveGeneration(
        conversationID: UUID
    ) async throws -> ConversationGenerationRecovery?
}
