import Foundation
import ImageIO
import UIKit

@MainActor final class ProfileViewModel {
    let nickname: String
    let email: String
    let avatarText: String

    private let service: any ProfileService
    private(set) var avatarData: Data?

    init(user: AuthUser, service: any ProfileService) {
        self.service = service
        nickname = user.nickname
        email = user.email
        avatarText = user.nickname.first.map { String($0) } ?? "?"
    }

    func loadAvatar() async throws {
        let savedAvatar = try await service.loadMyAvatar()

        if avatarData == nil {
            avatarData = savedAvatar
        }
    }

    func saveAvatar(from photoData: Data) async throws {
        guard let source = CGImageSourceCreateWithData(
            photoData as CFData,
            nil
        ) else {
            throw AvatarPreparationError.invalidPhoto
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ), let jpegData = UIImage(cgImage: thumbnail).jpegData(
            compressionQuality: 0.85
        ) else {
            throw AvatarPreparationError.invalidPhoto
        }

        try await service.uploadMyAvatar(jpegData)
        avatarData = jpegData
    }

    private enum AvatarPreparationError: LocalizedError {
        case invalidPhoto

        var errorDescription: String? {
            "无法处理这张照片，请重新选择。"
        }
    }
}
