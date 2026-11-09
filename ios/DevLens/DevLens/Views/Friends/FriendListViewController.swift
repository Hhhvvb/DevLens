import UIKit

final class FriendListViewController: UITableViewController {
    private let viewModel: FriendListViewModel
    private let addFriendHeader = AddFriendHeaderView()

    init(viewModel: FriendListViewModel) {
        self.viewModel = viewModel
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init(viewModel:) 创建好友列表")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "好友"
        addFriendHeader.onAddFriend = { [weak self] in
            self?.showAddFriendPrompt()
        }

        addFriendHeader.frame.size = CGSize(
            width: tableView.bounds.width,
            height: 88
        )
        tableView.tableHeaderView = addFriendHeader

        tableView.allowsSelection = false
        tableView.register(
            UITableViewCell.self,
            forCellReuseIdentifier: "FriendCell"
        )

        tableView.register(
            FriendRequestCell.self,
            forCellReuseIdentifier: "FriendRequestCell"
        )

        contentUnavailableConfiguration = UIContentUnavailableConfiguration.loading()

        Task { [weak self] in
            await self?.loadFriends()
        }
    }

    private func loadFriends() async {
        do {
            try await viewModel.load()
            tableView.reloadData()

            contentUnavailableConfiguration = nil
        } catch is CancellationError {
            return
        } catch {
            var configuration = UIContentUnavailableConfiguration.empty()
            configuration.text = "无法加载好友"
            configuration.secondaryText = error.localizedDescription
            contentUnavailableConfiguration = configuration
        }
    }

    override func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        if section == 0 {
            return viewModel.incomingRequests.count
        }

        return max(1, viewModel.friends.count)
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        if indexPath.section == 0 {
            let request = viewModel.incomingRequests[indexPath.row]
            let cell = tableView.dequeueReusableCell(
                withIdentifier: "FriendRequestCell",
                for: indexPath
            ) as! FriendRequestCell

            cell.configure(
                nickname: request.senderNickname,
                email: request.senderEmail
            )

            cell.onDecline = { [weak self] in
                Task { [weak self] in
                    await self?.respond(to: request.id, decision: .decline)
                }
            }

            cell.onAccept = { [weak self] in
                Task { [weak self] in
                    await self?.respond(to: request.id, decision: .accept)
                }
            }

            return cell
        }

        let cell = tableView.dequeueReusableCell(
            withIdentifier: "FriendCell",
            for: indexPath
        )

        if viewModel.friends.isEmpty {
            var content = cell.defaultContentConfiguration()
            content.text = "还没有好友"
            content.secondaryText = "可以从上方发送好友申请"
            cell.contentConfiguration = content
            return cell
        }

        let friend = viewModel.friends[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(
            systemName: "person.crop.circle",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 30)
        )
        content.imageProperties.tintColor = .systemIndigo
        content.text = friend.nickname
        content.secondaryText = friend.friendsSince.formatted(
            date: .abbreviated,
            time: .omitted
        )
        cell.contentConfiguration = content

        return cell
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        if section == 0 {
            return viewModel.incomingRequests.isEmpty ? nil : "收到的申请"
        }

        return viewModel.friends.isEmpty ? nil : "好友列表"
    }

    private func showAddFriendPrompt() {
        let alert = UIAlertController(
            title: "添加好友",
            message: "输入对方注册时使用的邮箱。",
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = "邮箱"
            textField.keyboardType = .emailAddress
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "发送申请", style: .default) { [weak self, weak alert] _ in
                guard let email = alert?.textFields?.first?.text else {
                    return
                }

                Task { [weak self] in
                    await self?.submitFriendRequest(email: email)
                }
            }
        )

        present(alert, animated: true)
    }

    private func submitFriendRequest(email: String) async {
        addFriendHeader.setSending(true)

        defer {
            addFriendHeader.setSending(false)
        }

        do {
            navigationItem.prompt = try await viewModel.sendFriendRequest(email: email)
        } catch is CancellationError {
            return
        } catch {
            navigationItem.prompt = error.localizedDescription
        }
    }

    private func respond(
        to id: UUID,
        decision: FriendRequestDecision
    ) async {
        guard tableView.isUserInteractionEnabled else { return }

        tableView.isUserInteractionEnabled = false

        defer {
            tableView.isUserInteractionEnabled = true
        }

        do {
            try await viewModel.respond(to: id, decision: decision)
        } catch is CancellationError {
            return
        } catch {
            navigationItem.prompt = error.localizedDescription
            return
        }

        navigationItem.prompt = decision == .accept ? "已接受好友申请" : "已拒绝好友申请"

        tableView.reloadData()
        await loadFriends()
    }
}
