import UIKit

final class RegistrationView: UIView {
    let emailField = UITextField()
    let nicknameField = UITextField()
    let passwordField = UITextField()
    let tokenField = UITextField()
    let primaryButton = UIButton(type: .system)
    let editButton = UIButton(type: .system)

    private let noticeLabel = UILabel()
    private let errorLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground

        configure(emailField, placeholder: "邮箱", contentType: .username)
        emailField.keyboardType = .emailAddress
        emailField.autocapitalizationType = .none
        emailField.autocorrectionType = .no

        configure(nicknameField, placeholder: "昵称", contentType: .nickname)

        configure(
            passwordField,
            placeholder: "密码（至少 15 个字符）",
            contentType: .newPassword
        )
        passwordField.isSecureTextEntry = true

        configure(tokenField, placeholder: "邮箱验证 Token", contentType: .oneTimeCode)
        tokenField.autocapitalizationType = .none
        tokenField.autocorrectionType = .no

        for label in [noticeLabel, errorLabel] {
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 0
        }

        noticeLabel.textColor = .secondaryLabel
        errorLabel.textColor = .systemRed

        var editConfiguration = UIButton.Configuration.plain()
        editConfiguration.title = "返回修改"
        editButton.configuration = editConfiguration

        setMinimumHeight(48, for: primaryButton)
        setMinimumHeight(44, for: editButton)

        let stack = UIStackView(arrangedSubviews: [
            emailField, nicknameField, passwordField,
            noticeLabel, tokenField, errorLabel,
            primaryButton, editButton
        ])
        stack.axis = .vertical
        stack.spacing = 16

        let scrollView = UIScrollView()
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        scrollView.addSubview(stack)

        let content = scrollView.contentLayoutGuide

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),

            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -48
            )
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init(frame:) 创建注册视图")
    }

    func render(_ state: RegistrationViewState) {
        switch state {
        case .form(let error):
            tokenField.text = nil
            display(form: true, title: "发送验证邮件", error: error)

        case .sendingEmail:
            display(form: true, title: "正在发送...", busy: true)

        case let .verification(email, notice, error):
            passwordField.text = nil
            display(
                form: false,
                title: "验证邮箱",
                notice: "\(email)\n\(notice)",
                error: error
            )

        case let .verifying(email, notice):
            display(
                form: false,
                title: "正在验证...",
                busy: true,
                notice: "\(email)\n\(notice)"
            )

        case .completed(_, let message):
            tokenField.text = nil
            display(form: false, title: "返回登录", notice: message, completed: true)
        }
    }

    private func display(
        form: Bool,
        title: String,
        busy: Bool = false,
        notice: String? = nil,
        error: String? = nil,
        completed: Bool = false
    ) {
        for field in [emailField, nicknameField, passwordField] {
            field.isHidden = !form
        }

        tokenField.isHidden = form || completed
        editButton.isHidden = form || completed
        noticeLabel.text = notice
        noticeLabel.isHidden = notice == nil
        errorLabel.text = error
        errorLabel.isHidden = error == nil

        let controls: [UIControl] = [
            emailField, nicknameField, passwordField, tokenField, primaryButton, editButton
        ]

        for control in controls {
            control.isEnabled = !busy
        }

        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.cornerStyle = .medium
        configuration.showsActivityIndicator = busy
        primaryButton.configuration = configuration
    }

    private func configure(
        _ field: UITextField,
        placeholder: String,
        contentType: UITextContentType
    ) {
        field.placeholder = placeholder
        field.accessibilityLabel = placeholder
        field.textContentType = contentType
        field.borderStyle = .roundedRect
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        setMinimumHeight(48, for: field)
    }

    private func setMinimumHeight(_ height: CGFloat, for view: UIView) {
        let constraint = view.heightAnchor.constraint(greaterThanOrEqualToConstant: height)
        constraint.priority = .defaultHigh
        constraint.isActive = true
    }
}
