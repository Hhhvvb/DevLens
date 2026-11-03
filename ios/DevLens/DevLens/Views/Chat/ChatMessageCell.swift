import UIKit
import SwiftUI

final class ChatMessageCell: UICollectionViewCell {
    private let messageView = ChatMessageContentView(frame: .zero)

    override init(frame: CGRect) {
        super.init(frame: frame)

        messageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(messageView)

        NSLayoutConstraint.activate([
            messageView.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: 12
            ),
            messageView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: 16
            ),
            messageView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -16
            ),
            messageView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -12
            )
        ])
    }

    func configure(
        with message: ChatMessage,
        onShowSources: (() -> Void)? = nil
    ) {
        messageView.onShowSources = onShowSources
        messageView.configure(with: message)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        messageView.onShowSources = nil
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init(frame:) 创建消息单元格")
    }
}

private final class MessageCellPreviewController: UICollectionViewController {
    private let messages: [ChatMessage] = [
        ChatMessage(
            role: .user,
            text: "为什么取消请求后还要检查取消状态？"
        ),
        ChatMessage(
            role: .assistant,
            text: """
            ## 取消是协作式的

            调用 `cancel()` 后，任务仍可能继续执行。

            ```swift
            guard !Task.isCancelled else { return }
            ```

            > 在更新界面之前检查取消状态。

            - 保留已经生成的内容。
            - 避免旧任务覆盖新的状态。
            """
        ),
        ChatMessage(
            role: .user,
            text: "明白了，**这里应该保留原始星号**。"
        ),
        ChatMessage(
            role: .assistant,
            text: "是的，用户消息保留原文，**AI 回答支持 Markdown**。"
        )
    ]

    private let registration =
        UICollectionView.CellRegistration<ChatMessageCell, ChatMessage> {
            cell, _, message in
            cell.configure(with: message)
        }

    init() {
        var configuration = UICollectionLayoutListConfiguration(
            appearance: .plain
        )
        configuration.showsSeparators = false

        let layout = UICollectionViewCompositionalLayout.list(
            using: configuration
        )

        super.init(collectionViewLayout: layout)
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init() 创建预览列表")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "消息单元格"
        collectionView.backgroundColor = .systemBackground
        collectionView.allowsSelection = false
    }

    override func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        messages.count
    }

    override func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        collectionView.dequeueConfiguredReusableCell(
            using: registration,
            for: indexPath,
            item: messages[indexPath.item]
        )
    }
}

#Preview("消息单元格列表") {
    UINavigationController(
        rootViewController: MessageCellPreviewController()
    )
}
