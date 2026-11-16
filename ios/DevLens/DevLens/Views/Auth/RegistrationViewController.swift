import UIKit

final class RegistrationViewController: UIViewController {
    private let registrationView = RegistrationView(frame: .zero)
    private let viewModel: RegistrationViewModel
    private var submitTask: Task<Void, Never>?

    var onVerified: ((String) -> Void)?

    init(viewModel: RegistrationViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init(viewModel:) 创建注册页面")
    }

    override func loadView() {
        view = registrationView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "创建账号"

        registrationView.primaryButton.addAction(
            UIAction { [weak self] _ in self?.submit() },
            for: .touchUpInside
        )

        registrationView.editButton.addAction(
            UIAction { [weak self] _ in
                self?.view.endEditing(true)
                self?.viewModel.returnToForm()
            },
            for: .touchUpInside
        )

        viewModel.onStateChanged = { [weak self] state in
            self?.registrationView.render(state)
        }
        registrationView.render(viewModel.state)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if isMovingFromParent {
            submitTask?.cancel()
        }
    }

    private func submit() {
        guard submitTask == nil else { return }

        if case let .completed(email, _) = viewModel.state {
            onVerified?(email)
            navigationController?.popViewController(animated: true)
            return
        }

        view.endEditing(true)

        submitTask = Task { [weak self] in
            guard let self else { return }
            defer { self.submitTask = nil }

            switch self.viewModel.state {
            case .form:
                await self.viewModel.register(
                    email: self.registrationView.emailField.text ?? "",
                    password: self.registrationView.passwordField.text ?? "",
                    nickname: self.registrationView.nicknameField.text ?? ""
                )
            case .verification:
                await self.viewModel.verifyEmail(
                    token: self.registrationView.tokenField.text ?? ""
                )

            case .sendingEmail, .verifying, .completed:
                break
            }
        }
    }
}
