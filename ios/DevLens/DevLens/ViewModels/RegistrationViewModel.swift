import Foundation

nonisolated enum RegistrationViewState {
    case form(error: String?)
    case sendingEmail
    case verification(email: String, notice: String, error: String?)
    case verifying(email: String, notice: String)
    case completed(email: String, message: String)
}

@MainActor
final class RegistrationViewModel {
    private let service: any AuthService

    var onStateChanged: ((RegistrationViewState) -> Void)?

    private(set) var state: RegistrationViewState = .form(error: nil) {
        didSet { onStateChanged?(state) }
    }

    init(service: any AuthService) {
        self.service = service
    }

    func register(email: String, password: String, nickname: String) async {
        guard case .form = state else { return }

        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !email.isEmpty else {
            state = .form(error: "请输入邮箱。")
            return
        }

        guard (1...40).contains(nickname.unicodeScalars.count) else {
            state = .form(error: "请输入 1 到 40 个字符的昵称。")
            return
        }

        guard (15...128).contains(password.unicodeScalars.count) else {
            state = .form(error: "密码长度须为 15 到 128 个字符。")
            return
        }

        let request = RegisterRequest(
            email: email,
            password: password,
            nickname: nickname
        )

        state = .sendingEmail

        do {
            let response = try await service.register(request)
            try Task.checkCancellation()
            state = .verification(email: email, notice: response.message, error: nil)
        } catch {
            let message = error is CancellationError || Task.isCancelled ? nil : error.localizedDescription
            state = .form(error: message)
        }
    }

    func verifyEmail(token: String) async {
        guard case let .verification(email, notice, _) = state else { return }

        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !token.isEmpty else {
            state = .verification(
                email: email,
                notice: notice,
                error: "请输入邮件里的验证 token。"
            )
            return
        }

        state = .verifying(email: email, notice: notice)

        do {
            let response = try await service.verifyEmail(
                VerifyEmailRequest(token: token)
            )

            try Task.checkCancellation()
            state = .completed(email: email, message: response.message)
        } catch {
            let message = error is CancellationError || Task.isCancelled ? nil : error.localizedDescription

            state = .verification(email: email, notice: notice, error: message)
        }
    }

    func returnToForm() {
        guard case .verification = state else { return }
        state = .form(error: nil)
    }
}
