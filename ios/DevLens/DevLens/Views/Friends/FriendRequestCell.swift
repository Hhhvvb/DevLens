import UIKit
import SwiftUI

final class FriendRequestCell: UITableViewCell {
    private let declineButton = UIButton(type: .system)
    private let acceptButton = UIButton(type: .system)
    private let identityView = UIListContentView(configuration: .cell())

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
        declineButton.accessibilityLabel = "拒接好友申请"

        var acceptStyle = UIButton.Configuration.filled()
        acceptStyle.image = UIImage(systemName: "checkmark")
        acceptStyle.baseBackgroundColor = .systemIndigo
        acceptStyle.baseForegroundColor = .white
        acceptStyle.cornerStyle = .capsule
        acceptButton.configuration = acceptStyle
        acceptButton.accessibilityLabel = "接受好友申请"

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
        actions.axis = .horizontal
        actions.spacing = 8
        actions.distribution = .fillEqually

        let row = UIStackView(arrangedSubviews: [identityView, actions])
        row.axis = .horizontal
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
        fatalError("请通过 UITableView 注册并创建好友申请单元格")
    }

    func configure(nickname: String, email: String) {
        var content = UIListContentConfiguration.cell()

        content.image = UIImage(
            systemName: "person.crop.circle",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 30)
        )
        content.imageProperties.tintColor = .systemIndigo
        content.text = nickname
        content.secondaryText = email
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 0

        identityView.configuration = content
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onDecline = nil
        onAccept = nil
    }
}

#Preview("好友申请", traits: .fixedLayout(width: 360, height: 88)) {
    let cell = FriendRequestCell(style: .default, reuseIdentifier: nil)
    cell.configure(nickname: "小林", email: "xiaolin@example.com")
    return cell
}
