import UIKit
import SwiftUI

final class ChatViewController:
    UIViewController,
    UICollectionViewDataSource,
    UICollectionViewDelegate {
    private var conversation: Conversation
    private var messages: [ChatMessage] {
        get {
            conversation.messages
        }
        set {
            conversation.messages = newValue
        }
    }
    private let viewModel: QuestionViewModel
    private var activeReplyID: UUID?
    private let collectionView: UICollectionView
    private let messageInputView = MessageInputView()
    private var renderTask: Task<Void, Never>?
    private var pendingStreamingState: QuestionViewState?
    private var shouldFollowLatest = true
    private var shouldResumeAfterScrolling = false
    private let latestButton = UIButton(type: .system)
    var onSaveConversation: ((Conversation) -> Task<Void, Error>)?
    private var lastSaveAt: Date?

    private lazy var messageRegistration = UICollectionView.CellRegistration<ChatMessageCell, ChatMessage> {
        [weak self] cell, _, message in

        let messageID = message.id

        cell.configure(
            with: message,
            onShowSources: { [weak self] in
                self?.showSources(for: messageID)
            }
        )
    }

    init(
        conversation: Conversation = Conversation(),
        apiClient: any QuestionService
    ) {
        self.conversation = conversation
        self.viewModel = QuestionViewModel(apiClient: apiClient)

        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.showsSeparators = false

        let layout = UICollectionViewCompositionalLayout.list(using: configuration)

        self.collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: layout
        )

        super.init(nibName: nil, bundle: nil)

        _ = messageRegistration
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init(messages:) 创建会话页面")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "DevLens"

        view.backgroundColor = .systemBackground
        collectionView.backgroundColor = .systemBackground
        collectionView.allowsSelection = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.keyboardDismissMode = .onDrag
        collectionView.alwaysBounceVertical = true

        setupLayout()
        setupLatestButton()

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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        followLatestIfNeeded()
        updateLatestButtonVisibility()
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

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first,
              messages.indices.contains(indexPath.item) else {
            return nil
        }

        let text = messages[indexPath.item].text

        guard !text.isEmpty else {
            return nil
        }

        return UIContextMenuConfiguration(
            identifier: nil,
            previewProvider: nil
        ) { _ in
            let copyAction = UIAction(
                title: "复制消息",
                image: UIImage(systemName: "doc.on.doc")
            ) { _ in
                UIPasteboard.general.string = text
            }

            return UIMenu(children: [copyAction])
        }
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

        let history = messages
            .filter {
                !$0.text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            }
            .map { message in
                var content = message.text

                if message.role == .assistant,
                   let statusText = message.statusText {
                    content = """
                    [此问答带有状态提示：\(statusText)]
                    \(message.text)
                    """
                }

                return HistoryMessage(
                    role: message.role,
                    content: content
                )
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

        shouldFollowLatest = true

        UIView.performWithoutAnimation {
            collectionView.insertItems(at: [questionPath, replyPath])

            collectionView.layoutIfNeeded()
            scrollToLatest()
        }

        viewModel.submit(
            text,
            history: history
        )
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
        let statusText: String?

        switch state {
        case .idle:
            return

        case .loading:
            text = ""
            statusText = "正在思考..."

        case .streaming(let answer):
            text = answer
            statusText = nil

        case .success(let response):
            messages[index].sourceChunks = response.sourceChunks
            text = response.answer
            statusText = nil

        case .failure(let answer, let message):
            text = answer
            statusText = answer.isEmpty ? message : "回答中断\n\(message)"

        case .cancelled(let answer):
            text = answer
            statusText = "已停止生成。"
        }

        messages[index].text = text
        messages[index].statusText = statusText

        UIView.performWithoutAnimation {
            collectionView.reconfigureItems(at: [IndexPath(item: index, section: 0)])

            collectionView.layoutIfNeeded()
            followLatestIfNeeded()
            updateLatestButtonVisibility()
        }

        switch state {
        case .loading:
            persistMessages(force: true)

        case .streaming:
            persistMessages(force: false)

        default:
            activeReplyID = nil
            persistMessages(force: true)
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

    private var isUserDragging: Bool {
        let state = collectionView.panGestureRecognizer.state
        return state == .began || state == .changed
    }

    private var bottomOffsetY: CGFloat {
        let inset = collectionView.adjustedContentInset

        return max(-inset.top, collectionView.contentSize.height - collectionView.bounds.height + inset.bottom)
    }

    private var isNearBottom: Bool {
        bottomOffsetY - collectionView.contentOffset.y <= 44
    }

    private func scrollToLatest() {
        guard !messages.isEmpty else {
            return
        }

        let target = CGPoint(
            x: collectionView.contentOffset.x,
            y: bottomOffsetY
        )

        guard abs(target.y - collectionView.contentOffset.y) > 0.5 else {
            return
        }

        collectionView.setContentOffset(target, animated: false)
    }

    private func followLatestIfNeeded() {
        guard shouldFollowLatest,
              !collectionView.isTracking,
              !isUserDragging,
              !collectionView.isDecelerating else {
            return
        }

        scrollToLatest()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        shouldFollowLatest = false
        shouldResumeAfterScrolling = false
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        if decelerate {
            resumeFollowingIfNeeded()
        } else {
            finishUserScrolling()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finishUserScrolling()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateLatestButtonVisibility()

        guard isUserDragging || scrollView.isDecelerating else {
            return
        }

        let velocityY = scrollView.panGestureRecognizer
            .velocity(in: scrollView).y

        if isUserDragging && velocityY > 0 {
            shouldResumeAfterScrolling = false
        } else if isNearBottom {
            shouldResumeAfterScrolling = true
        }

        resumeFollowingIfNeeded()
    }

    private func resumeFollowingIfNeeded() {
        guard viewModel.state.isLoading,
              !shouldFollowLatest,
              shouldResumeAfterScrolling,
              !collectionView.isTracking,
              !isUserDragging else {
            return
        }

        shouldFollowLatest = true

        if #available(iOS 17.4, *) {
            collectionView.stopScrollingAndZooming()
        }

        followLatestIfNeeded()
    }

    private func finishUserScrolling() {
        guard viewModel.state.isLoading else {
            shouldFollowLatest = false
            shouldResumeAfterScrolling = false
            return
        }

        shouldFollowLatest = shouldResumeAfterScrolling || isNearBottom
        followLatestIfNeeded()
    }

    private func setupLatestButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "回到最新"
        configuration.image = UIImage(systemName: "arrow.down")
        configuration.imagePadding = 6
        configuration.cornerStyle = .capsule

        latestButton.configuration = configuration
        latestButton.isHidden = true
        latestButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(latestButton)

        NSLayoutConstraint.activate([
            latestButton.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -16
            ),
            latestButton.bottomAnchor.constraint(
                equalTo: messageInputView.topAnchor,
                constant: -12
            ),
            latestButton.heightAnchor.constraint(
                greaterThanOrEqualToConstant: 44
            )
        ])

        latestButton.addAction(
            UIAction { [weak self] _ in
                self?.jumpToLatest()
            },
            for: .touchUpInside
        )
    }

    private func jumpToLatest() {
        guard !messages.isEmpty else {
            return
        }

        shouldResumeAfterScrolling = false

        if #available(iOS 17.4, *) {
            collectionView.stopScrollingAndZooming()
        }

        shouldFollowLatest = viewModel.state.isLoading

        collectionView.layoutIfNeeded()
        scrollToLatest()
        updateLatestButtonVisibility()
    }

    private func updateLatestButtonVisibility() {
        latestButton.isHidden = messages.isEmpty || isNearBottom
    }

    private func showSources(for messageID: UUID) {
        guard let message = messages.first(
            where: { $0.id == messageID }
        ), message.role == .assistant, !message.sourceChunks.isEmpty else {
            return
        }

        view.endEditing(true)

        let sourceList = SourceListViewController(sources: message.sourceChunks)

        navigationController?.pushViewController(sourceList, animated: true)
    }

    private func persistMessages(force: Bool) {
        let now = Date()

        if !force,
           let lastSaveAt,
           now.timeIntervalSince(lastSaveAt) < 1 {
            return
        }

        lastSaveAt = now

        let operation = saveCurrentConversation()

        Task { [weak self] in
            do {
                try await operation.value
            } catch {
                guard let self else {
                    return
                }

                let alert = UIAlertController(
                    title: "保存会话失败",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )

                alert.addAction(
                    UIAlertAction(title: "确定", style: .default)
                )

                let presenter = self.navigationController?.topViewController ?? self

                presenter.present(alert, animated: true)
            }
        }
    }

    private func saveCurrentConversation() -> Task<Void, Error> {
        conversation.updatedAt = Date()

        if let firstQuestion = messages.first(
            where: { $0.role == .user }
        ) {
            conversation.title = String(
                firstQuestion.text.prefix(20)
            )
        }

        guard let onSaveConversation else {
            return Task {
                throw ConversationStoreError.unavailable
            }
        }

        return onSaveConversation(conversation)
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
