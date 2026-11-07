import Foundation

nonisolated enum LoginViewState {
    case idle
    case loading
    case failure(String)
    case success(LoginResponse)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }

        return false
    }
}

@MainActor
final class LoginViewModel {
    private let authSession: AuthSession?
    var onStateChanged: ((LoginViewState) -> Void)?

    private(set) var state: LoginViewState = .idle {
        didSet {
            onStateChanged?(state)
        }
    }

    init(authSession: AuthSession? = nil) {
        self.authSession = authSession
    }

    func validationMessage(
        email rawEmail: String,
        password: String
    ) -> String? {
        let email = rawEmail.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !email.isEmpty else {
            return "请输入邮箱。"
        }

        let parts = email.split(
            separator: "@",
            omittingEmptySubsequences: false
        )

        guard parts.count == 2,
              parts.allSatisfy({ !$0.isEmpty }),
              email.rangeOfCharacter(
                from: .whitespacesAndNewlines
              ) == nil else {
            return "请检查邮箱格式。"
        }

        guard !password.isEmpty else {
            return "请输入密码。"
        }

        return nil
    }

    func submit(
        email rawEmail: String,
        password: String,
        using service: any AuthService
    ) async {
        guard !state.isLoading else {
            return
        }

        if let message = validationMessage(
            email: rawEmail,
            password: password
        ) {
            state = .failure(message)
            return
        }

        let email = rawEmail.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let request = LoginRequest(
            email: email,
            password: password
        )

        state = .loading

        do {
            let response = try await service.login(request)

            try Task.checkCancellation()

            if let authSession {
                try await authSession.accept(response)
            }

            try Task.checkCancellation()

            state = .success(response)
        } catch is CancellationError {
            state = .idle
        } catch {
            if Task.isCancelled {
                state = .idle
                return
            }

            state = .failure(error.localizedDescription)
        }
    }

    func clearError() {
        guard case .failure = state else {
            return
        }

        state = .idle
    }
}
