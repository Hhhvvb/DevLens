import Foundation

@MainActor
protocol ProfileService {
    func loadMyAvatar() async throws -> Data?
    func uploadMyAvatar(_ jpegData: Data) async throws
}
