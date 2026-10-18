import UIKit
import SwiftUI

final class MessageInputView: UIView {
    private let textField = UITextField()
    private let sendButton = UIButton(type: .system)

    var onSend: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupViews()

        sendButton.addAction(
            UIAction { [weak self] _ in
                self?.send()
            },
            for: .touchUpInside
        )
    }

    required init?(coder: NSCoder) {
        fatalError("请使用代码创建 MessageInputView")
    }

    private func setupViews() {
        backgroundColor = .secondarySystemBackground

        textField.placeholder = "输入关于代码的问题"
        textField.borderStyle = .roundedRect
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true

        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        sendButton.setTitle("发送", for: .normal)
        sendButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        sendButton.titleLabel?.adjustsFontForContentSizeCategory = true

        sendButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        sendButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = UIStackView(
            arrangedSubviews: [textField, sendButton]
        )
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: 16
            ),
            stack.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -16
            ),
            stack.topAnchor.constraint(
                equalTo: topAnchor,
                constant: 10
            ),
            stack.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -10
            ),
            textField.heightAnchor.constraint(
                greaterThanOrEqualToConstant: 44
            ),
            sendButton.heightAnchor.constraint(
                greaterThanOrEqualToConstant: 44
            )
        ])
    }

    private func send() {
        let text = (textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty, let onSend else {
            return
        }

        onSend(text)
        textField.text = ""
    }

    func setSending(_ isSending: Bool) {
        sendButton.isEnabled = !isSending
    }
}

#Preview("消息输入区") {
    let controller = UIViewController()
    controller.view.backgroundColor = .systemBackground

    let inputView = MessageInputView()
    inputView.translatesAutoresizingMaskIntoConstraints = false

    inputView.onSend = { text in
        print("待发送：\(text)")
    }

    controller.view.addSubview(inputView)

    NSLayoutConstraint.activate([
        inputView.leadingAnchor.constraint(
            equalTo: controller.view.safeAreaLayoutGuide.leadingAnchor,
            constant: 16
        ),
        inputView.trailingAnchor.constraint(
            equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor,
            constant: -16
        ),
        inputView.centerYAnchor.constraint(
            equalTo: controller.view.centerYAnchor
        ),
        inputView.heightAnchor.constraint(
            equalToConstant: 80
        )
    ])

    return controller
}
