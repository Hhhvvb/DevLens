import UIKit
import SwiftUI

final class LoginViewController: UIViewController {
    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let loginButton = UIButton(type: .system)
    private let viewModel = LoginViewModel()
    private let errorLabel = UILabel()
    private let authService: any AuthService
    private var loginTask: Task<Void, Never>?

    var onLoginSucceeded: ((LoginResponse) -> Void)?

    init(authService: any AuthService) {
        self.authService = authService

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init(authService:) 创建登录页面")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "登入 DevLens"
        view.backgroundColor = .systemBackground

        setupFields()
        setupLayout()

        loginButton.addAction(
            UIAction { [weak self] _ in
                self?.submitLogin()
            },
            for: .touchUpInside
        )

        for field in [emailField, passwordField] {
            field.addTarget(
                self,
                action: #selector(inputDidChange),
                for: .editingChanged
            )
        }

        viewModel.onStateChanged = { [weak self] state in
            self?.render(state)
        }

        render(viewModel.state)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        loginTask?.cancel()
    }

    private func setupFields() {
        emailField.placeholder = "邮箱"
        emailField.borderStyle = .roundedRect
        emailField.keyboardType = .emailAddress
        emailField.textContentType = .username
        emailField.autocapitalizationType = .none
        emailField.autocorrectionType = .no

        passwordField.placeholder = "密码"
        passwordField.borderStyle = .roundedRect
        passwordField.textContentType = .password
        passwordField.isSecureTextEntry = true

        for field in [emailField, passwordField] {
            field.font = .preferredFont(forTextStyle: .body)
            field.adjustsFontForContentSizeCategory = true
        }

        var configuration = UIButton.Configuration.filled()
        configuration.title = "登录"
        configuration.cornerStyle = .medium

        loginButton.configuration = configuration
        loginButton.isEnabled = true

        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
    }

    private func setupLayout() {
        let stackView = UIStackView(
            arrangedSubviews: [
                emailField,
                passwordField,
                errorLabel,
                loginButton
            ]
        )

        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stackView)

        let safeArea = view.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(
                equalTo: safeArea.topAnchor,
                constant: 48
            ),
            stackView.leadingAnchor.constraint(
                equalTo: safeArea.leadingAnchor,
                constant: 24
            ),
            stackView.trailingAnchor.constraint(
                equalTo: safeArea.trailingAnchor,
                constant: -24
            ),

            emailField.heightAnchor.constraint(
                greaterThanOrEqualToConstant: 48
            ),
            passwordField.heightAnchor.constraint(
                greaterThanOrEqualToConstant: 48
            ),
            loginButton.heightAnchor.constraint(
                greaterThanOrEqualToConstant: 48
            )

        ])
    }

    private func submitLogin() {
        guard loginTask == nil else {
            return
        }

        let email = emailField.text ?? ""
        let password = passwordField.text ?? ""

        view.endEditing(true)

        loginTask = Task { [weak self] in
            guard let self else {
                return
            }

            defer {
                self.loginTask = nil
            }

            await self.viewModel.submit(
                email: email,
                password: password,
                using: self.authService
            )
        }
    }

    @objc private func inputDidChange() {
        errorLabel.text = nil
        errorLabel.isHidden = true
    }

    private func render(_ state: LoginViewState) {
        let isLoading = state.isLoading

        emailField.isEnabled = !isLoading
        passwordField.isEnabled = !isLoading
        loginButton.isEnabled = !isLoading

        var configuration = loginButton.configuration
        configuration?.showsActivityIndicator = isLoading
        configuration?.title = isLoading ? "登录中..." : "登录"

        errorLabel.text = nil
        errorLabel.isHidden = true

        switch state {
        case .idle, .loading:
            break

        case .failure(let message):
            errorLabel.text = message
            errorLabel.isHidden = false

        case .success(let response):
            passwordField.text = ""
            loginButton.isEnabled = false
            configuration?.title = "登录成功"

            onLoginSucceeded?(response)
        }

        loginButton.configuration = configuration
    }
}

#if DEBUG

#Preview("登录失败") {
    UINavigationController(
        rootViewController: LoginViewController(
            authService: MockAuthService(scenario: .failure)
        )
    )
}

#Preview("登录成功") {
    UINavigationController(
        rootViewController: LoginViewController(
            authService: MockAuthService(scenario: .success)
        )
    )
}

#endif
