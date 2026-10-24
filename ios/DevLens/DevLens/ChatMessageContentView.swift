import UIKit
import SwiftUI

final class ChatMessageContentView: UIView {
    private let roleLabel = UILabel()
    private let stackView = UIStackView()
    private var bodyView: UIView?
    private var representedMessageID: UUID?
    private let sourceButton = UIButton(type: .system)

    var onShowSources: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        roleLabel.font = .preferredFont(forTextStyle: .headline)
        roleLabel.textColor = .label
        roleLabel.adjustsFontForContentSizeCategory = true
        roleLabel.numberOfLines = 0

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 8
        stackView.addArrangedSubview(roleLabel)

        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 12,
            leading: 0,
            bottom: 12,
            trailing: 0
        )

        sourceButton.configuration = configuration
        sourceButton.contentHorizontalAlignment = .leading
        sourceButton.isHidden = true

        sourceButton.addAction(
            UIAction { [weak self] _ in
                self?.onShowSources?()
            },
            for: .touchUpInside
        )

        stackView.addArrangedSubview(sourceButton)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func configure(with message: ChatMessage) {
        roleLabel.text = message.role == .user ? "你" : "DevLens"
        let sourceCount = message.sourceChunks.count
        let hasSources = message.role == .assistant && sourceCount > 0

        sourceButton.isHidden = !hasSources
        sourceButton.setTitle(
            hasSources ? "查看来源 · \(sourceCount) 个片段" : nil,
            for: .normal
        )

        if representedMessageID == message.id {
            switch message.role {
            case .user:
                if let label = bodyView as? UILabel {
                    label.text = message.text
                    return
                }

            case .assistant:
                if let answerView = bodyView as? MarkdownAnswerView {
                    answerView.update(markdown: message.text)
                    return
                }
            }
        }

        if let bodyView {
            stackView.removeArrangedSubview(bodyView)
            bodyView.removeFromSuperview()
        }

        let newBodyView: UIView

        switch message.role {
        case .user:
            let label = UILabel()
            label.text = message.text
            label.font = .preferredFont(forTextStyle: .body)
            label.textColor = .label
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true

            newBodyView = label

        case .assistant:
            newBodyView = MarkdownAnswerView(markdown: message.text)
        }

        stackView.insertArrangedSubview(newBodyView, at: 1)
        bodyView = newBodyView
        representedMessageID = message.id
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init(frame:) 创建消息内容视图")
    }
}

#Preview("消息内容") {
    let message = ChatMessage(
        role: .assistant,
        text: """
        ## 取消请求

        调用 `cancel()` 后，还需要检查 **取消状态**。

        ```swift
        guard !Task.isCancelled else { return }
        ```

        > 避免旧任务继续更新页面。
        """
    )

    let controller = UIViewController()
    controller.view.backgroundColor = .systemBackground

    let messageView = ChatMessageContentView(frame: .zero)
    messageView.configure(with: message)
    messageView.translatesAutoresizingMaskIntoConstraints = false

    let appendButton = UIBarButtonItem(
        title: "追加",
        primaryAction: UIAction { [weak messageView] _ in
            var updatedMessage = message
            updatedMessage.text += "\n\n这是后续生成的 **新内容**。"

            messageView?.configure(with: updatedMessage)
        }
    )

    let replaceButton = UIBarButtonItem(
        title: "换消息",
        primaryAction: UIAction { [weak messageView] _ in
            let anotherMessage = ChatMessage(
                role: .user,
                text: "这是另一条消息， **保留原始星号**。"
            )

            messageView?.configure(with: anotherMessage)
        }
    )

    controller.navigationItem.rightBarButtonItems = [
        appendButton,
        replaceButton
    ]

    controller.view.addSubview(messageView)

    let safeArea = controller.view.safeAreaLayoutGuide

    NSLayoutConstraint.activate([
        messageView.topAnchor.constraint(
            equalTo: safeArea.topAnchor,
            constant: 24
        ),
        messageView.leadingAnchor.constraint(
            equalTo: safeArea.leadingAnchor,
            constant: 16
        ),
        messageView.trailingAnchor.constraint(
            equalTo: safeArea.trailingAnchor,
            constant: -16
        )
    ])

    return UINavigationController(rootViewController: controller)
}
