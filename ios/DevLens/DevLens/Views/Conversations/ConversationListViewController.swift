import UIKit

final class ConversationListViewController: UITableViewController {
    private var conversations: [Conversation] = []
    private var store: ConversationStore?
    private var isCreating = false
    private var saveTask: Task<Void, Never>?
    private let conversationService: any ConversationService & GenerationService & ConversationInvitationService
    private var pendingConversation: Conversation?
    private var serverOnlyConversationIDs: Set<UUID> = []
    private var isOpeningConversation = false
    private var isLoadingServerConversations = false
    private let userID: UUID
    private let friendService: any FriendService
    private var memberCounts: [UUID: Int] = [:]
    private var unreadCounts: [UUID: Int] = [:]
    private var needsServerListRefresh = false

    init(
        userID: UUID,
        conversationService: any ConversationService & GenerationService & ConversationInvitationService,
        friendService: any FriendService
    ) {
        self.userID = userID
        self.conversationService = conversationService
        self.friendService = friendService
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init(conversationService:) 创建会话列表")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "会话"
        tableView.backgroundColor = .systemBackground

        let refresh = UIRefreshControl()

        refresh.addTarget(
            self,
            action: #selector(refreshServerList),
            for: .valueChanged
        )

        refreshControl = refresh

        tableView.alwaysBounceVertical = true

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "新建",
            primaryAction: UIAction { [weak self] _ in
                Task { [weak self] in
                    await self?.createConversation()
                }
            }
        )

        navigationItem.rightBarButtonItem?.isEnabled = false

        showPlaceholder("正在读取会话...")

        Task { [weak self] in
            await self?.loadConversations()
            await self?.loadServerConversations()
        }
    }

    private func loadConversations() async {
        do {
            let store = try ConversationStore(userID: userID)
            let conversations = try await store.load()

            self.store = store
            navigationItem.rightBarButtonItem?.isEnabled = true
            self.conversations = conversations.sorted {
                $0.updatedAt > $1.updatedAt
            }

            tableView.reloadData()

            if conversations.isEmpty {
                showPlaceholder("还没有会话")
            } else {
                tableView.backgroundView = nil
            }
        } catch {
            showPlaceholder("读取会话失败")

            let alert = UIAlertController(
                title: "无法读取会话",
                message: error.localizedDescription,
                preferredStyle: .alert
            )

            alert.addAction(
                UIAlertAction(title: "重试", style: .default) {
                    [weak self] _ in

                    Task { [weak self] in
                        await self?.loadConversations()
                    }
                }
            )

            alert.addAction(
                UIAlertAction(title: "取消", style: .cancel)
            )

            present(alert, animated: true)
        }
    }

    private func createConversation() async {
        guard let store,
              !isCreating,
              !isOpeningConversation,
              !isLoadingServerConversations else {
            return
        }

        isCreating = true
        navigationItem.rightBarButtonItem?.isEnabled = false

        defer {
            isCreating = false
            navigationItem.rightBarButtonItem?.isEnabled = !isOpeningConversation && !isLoadingServerConversations
            refreshServerListIfNeeded()
        }

        let pending = pendingConversation ?? Conversation()
        pendingConversation = pending

        do {
            let summary = try await conversationService.createConversation(
                CreateConversationRequest(
                    id: pending.id,
                    title: pending.title
                )
            )

            guard summary.id == pending.id else {
                throw APIError.invalidResponse
            }

            if serverOnlyConversationIDs.contains(summary.id),
               let existing = conversations.first(where: {
                   $0.id == summary.id
               }) {
                pendingConversation = nil
                openConversation(existing)
                return
            }

            let conversation: Conversation

            if let existing = conversations.first(where: {
                $0.id == summary.id
            }) {
                conversation = existing
            } else {
                var created = Conversation(
                    id: summary.id,
                    title: summary.title,
                    createdAt: summary.createdAt
                )

                created.updatedAt = summary.updatedAt
                conversation = created
            }

            try await store.upsert(conversation)
            memberCounts[summary.id] = summary.memberCount

            conversations.removeAll {
                $0.id == conversation.id
            }
            conversations.append(conversation)
            conversations.sort {
                $0.updatedAt > $1.updatedAt
            }

            pendingConversation = nil

            tableView.backgroundView = nil
            tableView.reloadData()

            openConversation(conversation)
        } catch {
            let alert = UIAlertController(
                title: "创建会话未完成",
                message: """
                \(error.localizedDescription)

                请稍后再次点击“新建”重试。
                """,
                preferredStyle: .alert
            )

            alert.addAction(
                UIAlertAction(title: "确定", style: .default)
            )

            present(alert, animated: true)
        }
    }

    private func showPlaceholder(_ text: String) {
        let label = UILabel()
        label.text = text
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0

        tableView.backgroundView = label
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        3
    }

    override func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        if section == 0 {
            return 1
        }
        return conversationsForSection(section).count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)

            var content = cell.defaultContentConfiguration()
            content.text = "会话邀请"
            content.image = UIImage(systemName: "envelope")
            content.imageProperties.tintColor = .systemIndigo

            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            return cell
        }

        let cell = tableView.dequeueReusableCell(
            withIdentifier: "ConversationCell"
        ) ?? UITableViewCell(
            style: .default,
            reuseIdentifier: "ConversationCell"
        )

        let conversation = conversationsForSection(indexPath.section)[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = conversation.title
        let updatedTime = conversation.updatedAt.formatted(
            date: .abbreviated,
            time: .shortened
        )

        let unreadCount = unreadCounts[conversation.id] ?? 0

        if unreadCount > 0 {
            let subtitle = NSMutableAttributedString(
                string: "\(updatedTime) · ",
                attributes: [.foregroundColor: UIColor.secondaryLabel]
            )

            subtitle.append(
                NSAttributedString(
                    string: "\(unreadCount) 条未读",
                    attributes: [.foregroundColor: UIColor.systemRed]
                )
            )

            content.secondaryAttributedText = subtitle
        } else {
            content.secondaryText = updatedTime
        }

        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator

        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 0 {
            showConversationInvitations()
            return
        }

        let conversation = conversationsForSection(indexPath.section)[indexPath.row]
        openConversation(conversation)
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        switch section {
        case 1: return "个人"
        case 2: return "共享"
        default: return nil
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshServerListIfNeeded()
    }

    private func showConversation(_ conversation: Conversation) {
        let controller = ChatViewController(
            conversation: conversation,
            apiClient: conversationService
        )

        if memberCounts[conversation.id] != nil || serverOnlyConversationIDs.contains(conversation.id) {
            controller.onLoadServerConversation = { [weak self] conversation in
                guard let self else { throw CancellationError() }
                return try await self.loadServerConversation(conversation)
            }
        }

        controller.onInviteFriends = { [weak self] conversationID in
            guard let self, let navigation = self.navigationController else {
                return
            }

            let viewModel = InviteFriendViewModel(
                conversationID: conversationID,
                friendService: self.friendService,
                invitationService: self.conversationService
            )
            let invitePage = InviteFriendViewController(viewModel: viewModel)
            invitePage.hidesBottomBarWhenPushed = true

            navigation.pushViewController(invitePage, animated: true)
        }

        controller.onSaveConversation = { [weak self] conversation in
            guard let self else {
                return Task {
                    throw ConversationStoreError.unavailable
                }
            }

            return self.saveConversation(conversation)
        }

        controller.hidesBottomBarWhenPushed = true

        navigationController?.pushViewController(
            controller,
            animated: true
        )
    }

    private func saveConversation(
        _ conversation: Conversation
    ) -> Task<Void, Error> {
        guard let store,
              let index = conversations.firstIndex(
                where: { $0.id == conversation.id }
              ) else {
            return Task {
                throw ConversationStoreError.unavailable
            }
        }

        conversations[index] = conversation
        conversations.sort {
            $0.updatedAt > $1.updatedAt
        }
        tableView.reloadData()

        let previousSave = saveTask

        let operation = Task {
            if let previousSave {
                await previousSave.value
            }

            try await store.upsert(conversation)
        }

        saveTask = Task {
            _ = await operation.result
        }

        return operation
    }

    private func loadServerMessages(
        conversationID: UUID
    ) async throws -> [ChatMessage] {
        let remoteMessages = try await conversationService.listMessages(
            conversationID: conversationID
        )

        guard remoteMessages.allSatisfy({
            $0.conversationID == conversationID
        }) else {
            throw APIError.invalidResponse
        }

        let sortedMessages = remoteMessages.sorted {
            $0.sequence < $1.sequence
        }

        return sortedMessages.map { message in
            message.toChatMessage()
        }
    }

    private func loadServerConversations(showErrors: Bool = true) async {
        guard store != nil,
              !isCreating,
              !isOpeningConversation else {
            refreshControl?.endRefreshing()
            return
        }

        guard !isLoadingServerConversations else {
            return
        }

        isLoadingServerConversations = true
        needsServerListRefresh = false

        tableView.isUserInteractionEnabled = false
        navigationItem.rightBarButtonItem?.isEnabled = false

        defer {
            isLoadingServerConversations = false

            tableView.isUserInteractionEnabled = true
            navigationItem.rightBarButtonItem?.isEnabled = !isCreating && !isOpeningConversation

            refreshControl?.endRefreshing()
            refreshServerListIfNeeded()
        }

        do {
            let summaries = try await conversationService.listConversations()
            memberCounts = Dictionary(
                uniqueKeysWithValues: summaries.map { ($0.id, $0.memberCount) }
            )
            unreadCounts = Dictionary(
                uniqueKeysWithValues: summaries.map{ ($0.id, $0.unreadCount ?? 0)}
            )

            for summary in summaries {
                if let index = conversations.firstIndex(where: { $0.id == summary.id }) {
                    conversations[index].updatedAt = max(conversations[index].updatedAt, summary.updatedAt)
                    continue
                }

                var conversation = Conversation(
                    id: summary.id,
                    title: summary.title,
                    createdAt: summary.createdAt
                )

                conversation.updatedAt = summary.updatedAt

                conversations.append(conversation)
                serverOnlyConversationIDs.insert(summary.id)
            }

            conversations.sort {
                $0.updatedAt > $1.updatedAt
            }

            tableView.reloadData()

            if conversations.isEmpty {
                showPlaceholder("还没有会话")
            } else {
                tableView.backgroundView = nil
            }
        } catch {
            guard showErrors else { return }

            let alert = UIAlertController(
                title: "无法读取服务器会话",
                message: error.localizedDescription,
                preferredStyle: .alert
            )

            alert.addAction(
                UIAlertAction(title: "确定", style: .default)
            )

            present(alert, animated: true)
        }
    }

    private func openConversation(_ conversation: Conversation) {
        guard !isOpeningConversation else {
            return
        }

        if let active = conversation.activeGeneration, !active.isConfirmed {
            showConversation(conversation)
            return
        }

        let isKnownToServer = memberCounts[conversation.id] != nil || serverOnlyConversationIDs.contains(conversation.id)

        guard isKnownToServer else {
            showConversation(conversation)
            return
        }

        isOpeningConversation = true
        tableView.isUserInteractionEnabled = false
        navigationItem.rightBarButtonItem?.isEnabled = false

        Task { [weak self] in
            guard let self else {
                return
            }

            defer {
                self.isOpeningConversation = false
                self.tableView.isUserInteractionEnabled = true
                self.navigationItem.rightBarButtonItem?.isEnabled = !self.isCreating
                refreshServerListIfNeeded()
            }

            do {
                let restored = try await self.loadServerConversation(conversation)

                let operation = self.saveConversation(restored)
                try await operation.value

                self.serverOnlyConversationIDs.remove(conversation.id)

                if self.pendingConversation?.id == restored.id {
                    self.pendingConversation = nil
                }

                self.showConversation(restored)
            } catch {
                let alert = UIAlertController(
                    title: "无法打开会话",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )

                alert.addAction(
                    UIAlertAction(title: "确定", style: .default)
                )

                self.present(alert, animated: true)
            }
        }
    }

    @objc private func refreshServerList() {
        Task { [weak self] in
            await self?.loadServerConversations()
        }
    }

    private func showConversationInvitations() {
        let viewModel = ConversationInvitationViewModel(service: conversationService)
        let controller = ConversationInvitationListViewController(viewModel: viewModel)

        controller.hidesBottomBarWhenPushed = true

        controller.onAcceptConversation = { [weak self, weak controller] id in
            guard let self,
                  let controller,
                  let navigation = self.navigationController,
                  navigation.topViewController === controller else {
                return
            }

            Task { [weak self] in
                guard let self else { return }

                await self.loadServerConversations()

                guard self.navigationController?.topViewController === controller,
                      let conversation = self.conversations.first(where: { $0.id == id }) else {
                    return
                }

                navigation.popViewController(animated: false)
                self.serverOnlyConversationIDs.insert(id)
                self.openConversation(conversation)
            }
        }

        navigationController?.pushViewController(controller, animated: true)
    }

    private func conversationsForSection(_ section: Int) -> [Conversation] {
        switch section {
        case 1:
            return conversations.filter { (memberCounts[$0.id] ?? 1) == 1 }
        case 2:
            return conversations.filter { (memberCounts[$0.id] ?? 1) > 1}
        default:
            return []
        }
    }

    func receiveConversationUpdate(_ update: ConversationUpdateEvent) {
        guard update.isInitial || !update.revisions.isEmpty || !update.removedConversationIDs.isEmpty else {
            return
        }

        if let chat = navigationController?.topViewController as? ChatViewController, update.isInitial || update.revisions.keys.contains(where: {
            UUID(uuidString: $0) == chat.conversationID
        }) {
            chat.requestConversationSync()
        }

        needsServerListRefresh = true
        refreshServerListIfNeeded()
    }

    private func refreshServerListIfNeeded() {
        Task { [weak self] in
            guard let self,
                  self.needsServerListRefresh,
                  self.viewIfLoaded?.window != nil,
                  self.navigationController?.topViewController === self,
                  self.store != nil,
                  !self.isCreating,
                  !self.isOpeningConversation,
                  !self.isLoadingServerConversations else {
                return
            }

            await self.loadServerConversations(showErrors: false)
        }
    }

    private func loadServerConversation(
        _ conversation: Conversation
    ) async throws -> Conversation {
        let recovery = try await conversationService.getActiveGeneration(conversationID: conversation.id)

        let messages = try await loadServerMessages(
            conversationID: conversation.id
        )

        var restored = conversation
        restored.messages = messages

        restored.activeGeneration = nil

        if let recovery {
            let snapshot = recovery.snapshot

            guard snapshot.conversationID == conversation.id,
                  recovery.request.conversationID == conversation.id,
                  recovery.request.requestID == snapshot.id,
                  messages.contains(where: {
                      $0.id == snapshot.questionMessageID && $0.role == .user
                  }),
                  messages.contains(where: {
                      $0.id == snapshot.answerMessageID && $0.role == .assistant
                  }) else {
                throw APIError.invalidResponse
            }

            restored.activeGeneration = ActiveGeneration(
                request: recovery.request,
                questionMessageID: snapshot.questionMessageID,
                answerMessageID: snapshot.answerMessageID,
                isConfirmed: true
            )
        }

        return restored
    }
}
