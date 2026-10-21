import UIKit
import SwiftUI

final class ChatViewController:
    UIViewController,
    UICollectionViewDataSource,
    UICollectionViewDelegate {
    private var messages: [ChatMessage]
    private let viewModel: QuestionViewModel
    private var activeReplyID: UUID?
    private let collectionView: UICollectionView
    private let messageInputView = MessageInputView()
    private var renderTask: Task<Void, Never>?
    private var pendingStreamingState: QuestionViewState?
    private var shouldFollowLatest = true
    private var shouldResumeAfterScrolling = false
    private let latestButton = UIButton(type: .system)

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

        view.backgroundColor = .systemBackground
        collectionView.backgroundColor = .systemBackground
        collectionView.allowsSelection = true
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
        shouldSelectItemAt indexPath: IndexPath
    ) -> Bool {
        let message = messages[indexPath.item]

        return message.role == .assistant && !message.sourceChunks.isEmpty
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        collectionView.deselectItem(
            at: indexPath,
            animated: false
        )
        view.endEditing(true)

        let message = messages[indexPath.item]
        guard !message.sourceChunks.isEmpty else { return }

        let sourceList = SourceListViewController(sources: message.sourceChunks)

        navigationController?.pushViewController(
            sourceList,
            animated: true
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
            messages[index].sourceChunks = response.sourceChunks

            if response.sourceChunks.isEmpty {
                text = response.answer
            } else {
                let count = response.sourceChunks.count

                text = response.answer + "\n\n—— 本次参考源码 ——\n" + "\n共 \(count) 个片段 · 点击这条回答查看 ›"
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
            followLatestIfNeeded()
            updateLatestButtonVisibility()
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
