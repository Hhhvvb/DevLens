import UIKit

final class ConversationInvitationListViewController: UITableViewController {
    private static let cellIdentifier = "ConversationInvitationCell"

    private let viewModel: ConversationInvitationViewModel
    private var isWorking = false

    var onAcceptConversation: ((UUID) -> Void)?

    init(viewModel: ConversationInvitationViewModel) {
        self.viewModel = viewModel
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init(viewModel:) 创建会话邀请列表")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "会话邀请"
        tableView.register(
            ConversationInvitationCell.self,
            forCellReuseIdentifier: Self.cellIdentifier
        )

        let refresh = UIRefreshControl()
        refresh.addAction(
            UIAction { [weak self] _ in self?.reloadInvitations() },
            for: .valueChanged
        )
        refreshControl = refresh

        contentUnavailableConfiguration = UIContentUnavailableConfiguration.loading()
        reloadInvitations()
    }

    override func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        viewModel.invitations.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: Self.cellIdentifier,
            for: indexPath
        ) as! ConversationInvitationCell

        let invitation = viewModel.invitations[indexPath.row]
        cell.configure(with: invitation)

        cell.onAccept = { [weak self] in
            self?.respond(to: invitation.id, accepting: true)
        }
        cell.onDecline = { [weak self] in
            self?.respond(to: invitation.id, accepting: false)
        }

        return cell
    }

    private func reloadInvitations() {
        performWork { controller in
            try await controller.viewModel.load()
            controller.renderInvitations()
        }
    }

    private func respond(to id: UUID, accepting: Bool) {
        performWork { controller in
            if accepting {
                let conversationID = try await controller.viewModel.accept(id: id)
                controller.renderInvitations()
                controller.onAcceptConversation?(conversationID)
            } else {
                try await controller.viewModel.decline(id: id)
                controller.renderInvitations()
            }
        }
    }

    private func renderInvitations() {
        tableView.reloadData()

        if viewModel.invitations.isEmpty {
            var configuration = UIContentUnavailableConfiguration.empty()
            configuration.text = "暂无会话邀请"
            contentUnavailableConfiguration = configuration
        } else {
            contentUnavailableConfiguration = nil
        }
    }

    private func performWork(
        _ work: @escaping @MainActor (ConversationInvitationListViewController) async throws -> Void
    ) {
        guard !isWorking else { return }

        isWorking = true

        Task { [weak self] in
            guard let self else { return }

            defer {
                self.isWorking = false
                self.refreshControl?.endRefreshing()
            }

            do {
                try await work(self)
            } catch is CancellationError {
                return
            } catch {
                self.contentUnavailableConfiguration = nil

                let alert = UIAlertController(
                    title: "无法处理会话邀请",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "好", style: .default))
                self.present(alert, animated: true)
            }
        }
    }
}
