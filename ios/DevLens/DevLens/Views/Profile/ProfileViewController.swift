import UIKit
import PhotosUI
import UniformTypeIdentifiers

final class ProfileViewController: UITableViewController {
    private let viewModel: ProfileViewModel
    private var profileHeaderView: ProfileHeaderView?
    private var isChangingAvatar = false
    var onShowFriends: (() -> Void)?
    var onSignOut: (@MainActor () async throws -> Void)?
    private var isSigningOut = false

    init(user: AuthUser, profileService: any ProfileService) {
        self.viewModel = ProfileViewModel(
            user: user,
            service: profileService
        )

        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init(user:) 创建个人资料页面")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "我的"

        tableView.register(
            UITableViewCell.self,
            forCellReuseIdentifier: "ProfileCell"
        )

        let header = ProfileHeaderView(
            nickname: viewModel.nickname,
            avatarText: viewModel.avatarText
        )

        header.onChangeAvatar = { [weak self] in
            self?.showAvatarPicker()
        }

        header.frame.size = CGSize(width: tableView.bounds.width, height: 188)
        profileHeaderView = header
        tableView.tableHeaderView = header
        Task { [weak self] in
            guard let self else { return }

            do {
                try await self.viewModel.loadAvatar()

                if let data = self.viewModel.avatarData {
                    self.profileHeaderView?.displayAvatar(data: data)
                }
            } catch is CancellationError {
                return
            } catch {
                let alert = UIAlertController(
                    title: "无法读取头像",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(
                    UIAlertAction(title: "确定", style: .default)
                )
                self.present(alert, animated: true)
            }
        }
    }

    override func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        return section == 0 ? 2 : 1
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
        cell.accessoryType = .none
        cell.selectionStyle = .default

        switch indexPath.section {
        case 0:
            if indexPath.row == 0 {
                content.text = "昵称"
                content.secondaryText = viewModel.nickname
            } else {
                content.text = "邮箱"
                content.secondaryText = viewModel.email
            }

        case 1:
            content.image = UIImage(systemName: "person.2")
            content.imageProperties.tintColor = .systemIndigo
            content.text = "好友"
            cell.accessoryType = .disclosureIndicator

        default:
            content.text = "退出登录"
            content.textProperties.color = .systemRed
            content.textProperties.alignment = .center
        }

        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        return section == 0 ? "个人资料" : nil
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    override func tableView(
        _ tableView: UITableView,
        willSelectRowAt indexPath: IndexPath
    ) -> IndexPath? {
        guard indexPath.section != 0, !isSigningOut else {
            return nil
        }

        return indexPath
    }

    override func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 1 {
            onShowFriends?()
        } else if indexPath.section == 2 {
            showSignOutConfirmation()
        }
    }

    private func showAvatarPicker() {
        guard !isChangingAvatar else { return }
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1

        let picker = PHPickerViewController(
            configuration: configuration
        )
        picker.delegate = self

        present(picker, animated: true)
    }

    private func showSignOutConfirmation() {
        let alert = UIAlertController(
            title: "退出登录？",
            message: "退出后将返回登录页。",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "退出登录", style: .destructive) { [weak self] _ in
                Task { [weak self] in
                    await self?.performSignOut()
                }
            }
        )

        present(alert, animated: true)
    }

    private func performSignOut() async {
        guard !isSigningOut, let onSignOut else { return }

        isSigningOut = true
        defer { isSigningOut = false }

        do {
            try await onSignOut()
        } catch {
            navigationItem.prompt = error.localizedDescription
        }
    }
}

extension ProfileViewController: PHPickerViewControllerDelegate {
    func picker(
        _ picker: PHPickerViewController,
        didFinishPicking results: [PHPickerResult]
    ) {
        picker.dismiss(animated: true)

        guard let result = results.first else {
            return
        }

        isChangingAvatar = true

        result.itemProvider.loadDataRepresentation(
            forTypeIdentifier: UTType.image.identifier
        ) { [weak self] data, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                defer {
                    self.isChangingAvatar = false
                }

                guard let data else {
                    let alert = UIAlertController(
                        title: "无法读取照片",
                        message: "请重新选择一张照片。",
                        preferredStyle: .alert
                    )
                    alert.addAction(
                        UIAlertAction(title: "确定", style: .default)
                    )
                    self.present(alert, animated: true)
                    return
                }

                do {
                    try await self.viewModel.saveAvatar(from: data)

                    if let avatarData = self.viewModel.avatarData {
                        self.profileHeaderView?.displayAvatar(data: avatarData)
                    }
                } catch {
                    let alert = UIAlertController(
                        title: "无法更换头像",
                        message: error.localizedDescription,
                        preferredStyle: .alert
                    )
                    alert.addAction(
                        UIAlertAction(title: "确定", style: .default)
                    )
                    self.present(alert, animated: true)
                }
            }
        }
    }
}
