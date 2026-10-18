import UIKit
import SwiftUI

final class ChatViewController: UIViewController, UICollectionViewDataSource {
    private var messages: [ChatMessage]
    private let viewModel: QuestionViewModel
    private var activeReplyID: UUID?
    private let collectionView: UICollectionView
    private let messageInputView = MessageInputView()
    private var renderTask: Task<Void, Never>?
    private var pendingStreamingState: QuestionViewState?

    private let messageRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, ChatMessage> {
        cell, _, message in
        var content = cell.defaultContentConfiguration()

        content.text = message.role == .user ? "你" : "DevLens"
        content.secondaryText = message.text

        content.textProperties.font = .preferredFont(forTextStyle: .headline)
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .body)
        content.secondaryTextProperties.numberOfLines = 0

        cell.contentConfiguration = content
        cell.accessories = []
    }

    init(
        message: [ChatMessage] = [],
        apiClient: any QuestionService
    ) {
        self.messages = message
        self.viewModel = QuestionViewModel(apiClient: apiClient)

        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.showsSeparators = false

        let layout = UICollectionViewCompositionalLayout.list(using: configuration)

        self.collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: layout
        )

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init(messages:) 创建会话页面")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "DevLens"
        collectionView.backgroundColor = .systemBackground
        collectionView.allowsSelection = false
        collectionView.dataSource = self
        collectionView.keyboardDismissMode = .onDrag
        collectionView.alwaysBounceVertical = true

        setupLayout()

        let dismissTap = UITapGestureRecognizer(
            target: self, action: #selector(dismissKeyboard)
        )

        dismissTap.cancelsTouchesInView = false
        collectionView.addGestureRecognizer(dismissTap)

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "停止",
            primaryAction: UIAction { [weak self] _ in
                self?.viewModel.cancel()
            }
        )

        messageInputView.onSend = { [weak self] text in
            self?.appendUserMessage(text)
        }

        viewModel.onStateChanged = { [weak self] state in
            self?.receiveState(state)
        }

        render(viewModel.state)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        messages.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        collectionView.dequeueConfiguredReusableCell(
            using: messageRegistration,
            for: indexPath,
            item: messages[indexPath.item]
        )
    }

    private func setupLayout() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        messageInputView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(collectionView)
        view.addSubview(messageInputView)

        let safeArea = view.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: safeArea.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: messageInputView.topAnchor),

            messageInputView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            messageInputView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            messageInputView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            messageInputView.heightAnchor.constraint(equalToConstant: 80)
        ])
    }

    private func appendUserMessage(_ rawText: String) {
        guard !viewModel.state.isLoading else {
            return
        }

        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            return
        }

        let firstNewIndex = messages.count
        let reply = ChatMessage(
            role: .assistant,
            text: "正在思考..."
        )

        messages.append(
            ChatMessage(role: .user, text: text)
        )
        messages.append(reply)

        activeReplyID = reply.id

        let questionPath = IndexPath(
            item: firstNewIndex,
            section: 0
        )
        let replyPath = IndexPath(
            item: firstNewIndex + 1,
            section: 0
        )

        collectionView.insertItems(at: [questionPath, replyPath])

        collectionView.scrollToItem(
            at: replyPath,
            at: .bottom,
            animated: true
        )

        viewModel.submit(text)
    }

    private func render(_ state: QuestionViewState) {
        navigationItem.rightBarButtonItem?.isEnabled = state.isLoading
        messageInputView.setSending(state.isLoading)

        guard let replyID = activeReplyID,
              let index = messages.firstIndex(
                where: { $0.id == replyID }
              ) else {
            return
        }

        let text: String

        switch state {
        case .idle:
            return

        case .loading:
            text = "正在思考..."

        case .streaming(let answer):
            text = answer

        case .success(let response):
            if response.sources.isEmpty {
                text = response.answer
            } else {
                text = response.answer + "\n\n—— 本次提供给模型的文件 ——\n" + response.sources.joined(separator: "\n")
            }

        case .failure(let message):
            text = message

        case .cancelled(let answer):
            text = answer.isEmpty ? "已停止生成。" : answer + "\n\n—— 已停止生成 ——"
        }

        messages[index].text = text

        UIView.performWithoutAnimation {
            collectionView.reconfigureItems(at: [IndexPath(item: index, section: 0)])

            collectionView.layoutIfNeeded()
        }

        if !state.isLoading {
            activeReplyID = nil
        }
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    private func receiveState(_ state: QuestionViewState) {
        guard case .streaming = state else {
            renderTask?.cancel()
            renderTask = nil
            pendingStreamingState = nil

            render(state)
            return
        }

        pendingStreamingState = state

        guard renderTask == nil else {
            return
        }

        renderTask = Task{ [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }

            guard let self, !Task.isCancelled else {
                return
            }

            self.renderTask = nil

            guard let latesState = self.pendingStreamingState else {
                return
            }

            self.pendingStreamingState = nil
            self.render(latesState)
        }
    }
}


#Preview("会话列表") {
    UINavigationController(
        rootViewController: ChatViewController(
            apiClient: MockQuestionService(
                scenario: .success
            )
        )
    )
}
