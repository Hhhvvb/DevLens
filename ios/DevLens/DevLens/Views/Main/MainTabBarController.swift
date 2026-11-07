import UIKit

final class MainTabBarController: UITabBarController {
    private let user: AuthUser
    private let conversationService: any ConversationService & GenerationService
    private let profileService: any ProfileService

    init(
        user: AuthUser,
        conversationService: any ConversationService & GenerationService,
        profileService: any ProfileService
    ) {
        self.user = user
        self.conversationService = conversationService
        self.profileService = profileService

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
