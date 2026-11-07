import UIKit

final class ProfileViewController: UITableViewController {
    private let user: AuthUser

    init(user: AuthUser) {
        self.user = user

        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init(user:) 创建个人资料页面")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "我的"
        tableView.allowsSelection = false

        tableView.register(
            UITableViewCell.self,
            forCellReuseIdentifier: "ProfileCell"
        )
    }

    override func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        return 2
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "ProfileCell",
            for: indexPath
        )

        var content = cell.defaultContentConfiguration()

        if indexPath.row == 0 {
            content.text = "昵称"
            content.secondaryText = user.nickname
        } else {
            content.text = "邮箱"
            content.secondaryText = user.email
        }

        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content

        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        return "个人资料"
    }
}
