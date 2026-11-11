import UIKit

final class ConversationInvitationCell: UITableViewCell {
    private let invitationView = UIListContentView(configuration: .cell())
    private let declineButton = UIButton(type: .system)
    private let acceptButton = UIButton(type: .system)

    var onDecline: (() -> Void)?
    var onAccept: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        var declineStyle = UIButton.Configuration.tinted()
        declineStyle.image = UIImage(systemName: "xmark")
        declineStyle.baseBackgroundColor = .systemGray
        declineStyle.baseForegroundColor = .label
        declineStyle.cornerStyle = .capsule
        declineButton.configuration = declineStyle
        declineButton.accessibilityLabel = "拒绝会话邀请"

        var acceptStyle = UIButton.Configuration.filled()
        acceptStyle.image = UIImage(systemName: "checkmark")
        acceptStyle.baseBackgroundColor = .systemIndigo
        acceptStyle.baseForegroundColor = .white
        acceptStyle.cornerStyle = .capsule
        acceptButton.configuration = acceptStyle
        acceptButton.accessibilityLabel = "接受会话邀请"

        declineButton.addAction(
            UIAction { [weak self] _ in self?.onDecline?() },
            for: .touchUpInside
        )
        acceptButton.addAction(
            UIAction { [weak self] _ in self?.onAccept?() },
            for: .touchUpInside
        )

        let actions = UIStackView(
            arrangedSubviews: [declineButton, acceptButton]
        )
        actions.spacing = 8
        actions.distribution = .fillEqually

        let row = UIStackView(arrangedSubviews: [invitationView, actions])
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)

        let margins = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            row.topAnchor.constraint(equalTo: margins.topAnchor),
            row.bottomAnchor.constraint(equalTo: margins.bottomAnchor),
            actions.widthAnchor.constraint(equalToConstant: 96),
            actions.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("请通过 UITableView 注册并创建会话邀请单元格")
    }

    func configure(with invitation: IncomingConversationInvitation) {
        var content = UIListContentConfiguration.cell()
        content.text = invitation.conversationTitle
        content.textProperties.numberOfLines = 0
        content.secondaryText = "邀请人 · \(invitation.inviterNickname)"
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 0
        invitationView.configuration = content
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onDecline = nil
        onAccept = nil
    }
}
