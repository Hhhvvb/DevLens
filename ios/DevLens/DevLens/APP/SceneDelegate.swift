//
//  SceneDelegate.swift
//  DevLens
//
//  Created by Firevsice on 2026/10/12.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    private let apiClient = APIClient()

    private lazy var authSession = AuthSession(
        service: apiClient,
        tokenStore: RefreshTokenStore()
    )

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let window = UIWindow(windowScene: windowScene)
        self.window = window

        authSession.onStateChanged = { [weak self] state in
            self?.renderAuthState(state)
        }

        renderAuthState(authSession.state)

        window.makeKeyAndVisible()

        Task {
            await authSession.restore()
        }
    }

    private func renderAuthState(_ state: AuthSessionState) {
        switch state {
        case .idle, .restoring:
            showStatus(
                title: "DevLens",
                message: "正在恢复登录..."
            )

        case .signedOut:
            showLogin()

        case .signedIn(let user):
            let conversationClient = APIClient(
                accessTokenProvider: { [weak session = authSession] in
                    session?.accessToken
                }
            )

            window?.rootViewController = MainTabBarController(
                user: user,
                conversationService: conversationClient
            )

        case .failure(let message):
            showStatus(
                title: "恢复登录失败",
                message: message,
                allowsLogin: true
            )
        }
    }

    @objc private func showLogin() {
        let controller = LoginViewController(
            authService: apiClient,
            authSession: authSession
        )

        window?.rootViewController = UINavigationController(
            rootViewController: controller
        )
    }

    private func showStatus(
        title: String,
        message: String,
        allowsLogin: Bool = false
    ) {
        let controller = UIViewController()
        controller.title = title
        controller.view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = message
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false

        controller.view.addSubview(label)

        let safeArea = controller.view.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(
                equalTo: safeArea.centerYAnchor
            ),
            label.leadingAnchor.constraint(
                equalTo: safeArea.leadingAnchor,
                constant: 24
            ),
            label.trailingAnchor.constraint(
                equalTo: safeArea.trailingAnchor,
                constant: -24
            )
        ])

        if allowsLogin {
            controller.navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: "密码登录",
                style: .plain,
                target: self,
                action: #selector(showLogin)
            )
        }

        window?.rootViewController = UINavigationController(
            rootViewController: controller
        )
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }


}
