import UIKit

final class ConversationListViewController: UITableViewController {
    private var conversations: [Conversation] = []
    private var store: ConversationStore?
    private var isCreating = false
    private var saveTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "会话"
        tableView.backgroundColor = .systemBackground

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
        }
    }

    private func loadConversations() async {
        do {
            let store = try ConversationStore()
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
        guard let store, !isCreating else {
            return
        }

        isCreating = true
        navigationItem.rightBarButtonItem?.isEnabled = false

        defer {
            isCreating = false
            navigationItem.rightBarButtonItem?.isEnabled = true
        }

        let conversation = Conversation()

        do {
            try await store.upsert(conversation)

            conversations.insert(conversation, at: 0)
            tableView.backgroundView = nil
            tableView.reloadData()

            openConversation(conversation)
        } catch {
            let alert = UIAlertController(
                title: "创建会话失败",
                message: error.localizedDescription,
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

    override func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        conversations.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "ConversationCell"
        ) ?? UITableViewCell(
            style: .default,
            reuseIdentifier: "ConversationCell"
        )

        let conversation = conversations[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = conversation.title
        content.secondaryText = conversation.updatedAt.formatted(
            date: .abbreviated,
            time: .shortened
        )

        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator

        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)

        let conversation = conversations[indexPath.row]
        openConversation(conversation)
    }

    private func openConversation(_ conversation: Conversation) {
        let controller = ChatViewController(
            message: conversation.messages,
            apiClient: APIClient()
        )

        controller.onMessagesChanged = { [weak self] messages in
            self?.updateConversation(
                id: conversation.id,
                messages: messages
            )
        }

        navigationController?.pushViewController(
            controller,
            animated: true
        )
    }

    private func updateConversation(
        id: UUID,
        messages: [ChatMessage]
    ) {
        guard let store,
              let index = conversations.firstIndex(
                where: { $0.id == id }
              ) else {
            return
        }

        conversations[index].messages = messages
        conversations[index].updatedAt = Date()

        if let firstQuestion = messages.first(
            where: { $0.role == .user }
        ) {
            conversations[index].title = String(firstQuestion.text.prefix(20))
        }

        let updatedConversation = conversations[index]

        conversations.sort {
            $0.updatedAt > $1.updatedAt
        }
        tableView.reloadData()

        let previousSave = saveTask

        saveTask = Task { [weak self] in
            if let previousSave {
                await previousSave.value
            }

            do {
                try await store.upsert(updatedConversation)
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
}
