import UIKit

final class ProfileHeaderView: UIView {
    private let avatarImageView = UIImageView()

    var onChangeAvatar: (() -> Void)?

    func displayAvatar(data: Data) {
        avatarImageView.image = UIImage(data: data)
    }

    init(nickname: String, avatarText: String) {
        super.init(frame: .zero)

        let avatar = UILabel()
        avatar.text = avatarText
        avatar.textAlignment = .center
        avatar.font = .systemFont(ofSize: 30, weight: .semibold)
        avatar.textColor = .systemIndigo
        avatar.backgroundColor = .systemIndigo.withAlphaComponent(0.15)
        avatar.layer.cornerRadius = 36
        avatar.clipsToBounds = true
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatar.addSubview(avatarImageView)

        NSLayoutConstraint.activate([
            avatarImageView.topAnchor.constraint(equalTo: avatar.topAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: avatar.bottomAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: avatar.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: avatar.trailingAnchor)
        ])

        let name = UILabel()
        name.text = nickname
        name.textAlignment = .center
        name.font = .preferredFont(forTextStyle: .headline)
        name.adjustsFontForContentSizeCategory = true

        let changeAvatarButton = UIButton(type: .system)
        changeAvatarButton.setTitle("更换头像", for: .normal)
        changeAvatarButton.addAction(
            UIAction { [weak self] _ in
                self?.onChangeAvatar?()
            },
            for: .touchUpInside
        )

        let stack = UIStackView(arrangedSubviews: [avatar, name, changeAvatarButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 72),
            avatar.heightAnchor.constraint(equalTo: avatar.widthAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: 20,
            ),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -20,
            )
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init(nickname:avatarText:) 创建资料顶部视图")
    }
}
