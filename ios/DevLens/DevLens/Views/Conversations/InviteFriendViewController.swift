import UIKit

final class InviteFriendViewController: UITableViewController {
    private let viewModel: InviteFriendViewModel
    private var isSending = false

    init(viewModel: InviteFriendViewModel) {
        self.viewModel = viewModel
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init(viewModel:) 创建邀请好友页面")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "邀请好友"

        contentUnavailableConfiguration = UIContentUnavailableConfiguration.loading()

        Task { [weak self] in
            await self?.loadFriends()
        }
    }

    private func loadFriends() async {
        do {
            try await viewModel.load()
            tableView.reloadData()

            if viewModel.friends.isEmpty {
                var configuration = UIContentUnavailableConfiguration.empty()
                configuration.text = "暂无好友"
                contentUnavailableConfiguration = configuration
            } else {
                contentUnavailableConfiguration = nil
            }
        } catch {
            contentUnavailableConfiguration = nil
            showMessage(
                title: "无法读取好友",
                message: error.localizedDescription
            )
        }
    }

    override func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        viewModel.friends.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let friend = viewModel.friends[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "InviteFriendCell") ?? UITableViewCell(style: .default, reuseIdentifier: "InviteFriendCell")

        var content = cell.defaultContentConfiguration()
        content.text = friend.nickname
        content.image = UIImage(systemName: "person.crop.circle")
        cell.contentConfiguration = content

        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !isSending else { return }

        let friend = viewModel.friends[indexPath.row]

        let alert = UIAlertController(
            title: "邀请 \(friend.nickname) 加入会话？",
            message: "对方接受后，将看到本会话的全部历史消息及引用的源码，并可在同一个会话中继续提问。",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "发送邀请", style: .default) { [weak self] _ in
            self?.sendInvitation(to: friend)
        })

        present(alert, animated: true)
    }

    private func sendInvitation(to friend: FriendSummary) {
        guard !isSending else { return }
        isSending = true

        Task { [weak self] in
            guard let self else { return }
            defer { self.isSending = false }

            do {
                try await self.viewModel.invite(friend)
                self.showMessage(title: "邀请已提交", message: nil)
            } catch {
                self.showMessage(
                    title: "无法发送邀请",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func showMessage(title: String, message: String?) {
        guard viewIfLoaded?.window != nil else { return }

        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}
