import UIKit

final class MainTabBarController: UITabBarController {
    private let user: AuthUser
    private let conversationService: any ConversationService & GenerationService
    private let profileService: any ProfileService
    private let friendService: any FriendService
    private let signOut: @MainActor () async throws -> Void

    init(
        user: AuthUser,
        conversationService: any ConversationService & GenerationService,
        profileService: any ProfileService,
        friendService: any FriendService,
        signOut: @escaping @MainActor () async throws -> Void
    ) {
        self.user = user
        self.conversationService = conversationService
        self.profileService = profileService
        self.friendService = friendService
        self.signOut = signOut

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("请使用 init(user:) 创建主页面")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let conversations = ConversationListViewController(
            userID: user.id,
            conversationService: conversationService
        )

        let profile = ProfileViewController(
            user: user,
            profileService: profileService
        )

        let signOut = self.signOut

        profile.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "退出",
            primaryAction: UIAction { [weak profile] _ in
                Task { @MainActor [weak profile] in
                    guard let profile else { return }

                    profile.navigationItem.leftBarButtonItem?.isEnabled = false

                    defer {
                        profile.navigationItem.leftBarButtonItem?.isEnabled = true
                    }

                    do {
                        try await signOut()
                    } catch {
                        profile.navigationItem.prompt = error.localizedDescription
                    }
                }

            }
        )

        let friendService = self.friendService

        profile.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "好友",
            primaryAction: UIAction { [weak profile] _ in
                let viewModel = FriendListViewModel(service: friendService)
                let controller = FriendListViewController(viewModel: viewModel)

                profile?.navigationController?.pushViewController(
                    controller,
                    animated: true
                )
            }
        )

        let conversationNavigation = UINavigationController(
            rootViewController: conversations
        )

        let profileNavigation = UINavigationController(
            rootViewController: profile
        )

        conversationNavigation.tabBarItem = UITabBarItem(
            title: "会话",
            image: UIImage(systemName: "bubble.left.and.bubble.right"),
            selectedImage: UIImage(systemName: "bubble.left.and.bubble.right.fill")
        )

        profileNavigation.tabBarItem = UITabBarItem(
            title: "我的",
            image: UIImage(systemName: "person.crop.circle"),
            selectedImage: UIImage(systemName: "person.crop.circle.fill")
        )

        viewControllers = [
            conversationNavigation,
            profileNavigation
        ]
    }
}
