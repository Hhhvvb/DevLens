import Foundation

@MainActor
protocol GenerationService {
    func createGeneration(
        _ input: CreateGenerationRequest
    ) async throws -> GenerationSnapshot

    func getGeneration(
        id: UUID
    ) async throws -> GenerationSnapshot

    func stopGeneration(
        id: UUID
    ) async throws -> GenerationSnapshot

    func subscribeGeneration(
        id: UUID,
        onUpdate: @MainActor (GenerationSnapshot) -> Void
    ) async throws -> GenerationSnapshot
}
