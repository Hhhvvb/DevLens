import UIKit

final class FriendListViewController: UITableViewController {
    private let viewModel: FriendListViewModel

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
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "添加",
            primaryAction: UIAction { [weak self] _ in
                self?.showAddFriendPrompt()
            }
        )
        tableView.allowsSelection = false
        tableView.register(
            UITableViewCell.self,
            forCellReuseIdentifier: "FriendCell"
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

            if viewModel.friends.isEmpty && viewModel.incomingRequests.isEmpty {
                var configuration = UIContentUnavailableConfiguration.empty()
                configuration.text = "还没有好友或收到的申请"
                contentUnavailableConfiguration = configuration
            } else {
                contentUnavailableConfiguration = nil
            }
        } catch is CancellationError {
            return
        } catch {
            var configuration = UIContentUnavailableConfiguration.empty()
            configuration.text = "无法加载好友"
            configuration.secondaryText = error.localizedDescription
        }
    }

    override func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        if section == 0 {
            return viewModel.incomingRequests.count
        }

        return viewModel.friends.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "FriendCell",
            for: indexPath
        )

        var content = cell.defaultContentConfiguration()

        if indexPath.section == 0 {
            let request = viewModel.incomingRequests[indexPath.row]
            content.text = request.senderNickname
            content.secondaryText = "请求添加你为好友"
        } else {
            let friend = viewModel.friends[indexPath.row]
            content.text = friend.nickname
            content.secondaryText = friend.friendsSince.formatted(
                date: .abbreviated,
                time: .omitted
            )
        }

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
        navigationItem.rightBarButtonItem?.isEnabled = false

        defer {
            navigationItem.rightBarButtonItem?.isEnabled = true
        }

        do {
            navigationItem.prompt = try await viewModel.sendFriendRequest(email: email)
        } catch is CancellationError {
            return
        } catch {
            navigationItem.prompt = error.localizedDescription
        }
    }
}
