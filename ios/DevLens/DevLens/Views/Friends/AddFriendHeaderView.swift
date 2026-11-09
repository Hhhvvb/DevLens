import UIKit

final class AddFriendHeaderView: UIView {
    private let button = UIButton(type: .system)

    var onAddFriend: (() -> Void)?

    init() {
        super.init(frame: .zero)

        var configuration = UIButton.Configuration.tinted()
        configuration.title = "添加好友"
        configuration.subtitle = "通过邮箱发送好友申请"
        configuration.image = UIImage(systemName: "person.badge.plus")
        configuration.imagePadding = 12
        configuration.titlePadding = 4
        configuration.baseForegroundColor = .systemIndigo
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 12,
            leading: 16,
            bottom: 12,
            trailing: 16
        )

        button.configuration = configuration
        button.contentHorizontalAlignment = .leading
        button.translatesAutoresizingMaskIntoConstraints = false

        button.addAction(
            UIAction { [weak self] _ in
                self?.onAddFriend?()
            },
            for: .touchUpInside
        )

        addSubview(button)

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            button.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            button.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init() 创建添加好友卡片")
    }

    func setSending(_ isSending: Bool) {
        button.isEnabled = !isSending
        button.configuration?.showsActivityIndicator = isSending
    }
}
